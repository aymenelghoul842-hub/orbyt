import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config.dart';
import '../languages.dart';
import 'audio_tune.dart';

class ChatService {
  ChatService({
    required this.video,
    this.interests = const [],
    this.username,
    this.language = kAnyLang,
  });
  final bool video;
  final List<String> interests;
  final String? username; // null = Anonymous
  String language; // language code you want to speak; 'any' = no preference
  String partnerLanguage = kAnyLang; // language of the current stranger

  late final io.Socket socket;
  bool _ready = false; // socket created (false if camera permission was denied)
  Map<String, dynamic> _ice = kIceConfig;
  RTCPeerConnection? _pc;
  MediaStream? _local;
  Future<void> _chain = Future.value();
  Future<void>? _pcReady;

  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();

  void Function(String status)? onStatus;
  void Function(String text, bool mine)? onMessage;
  void Function(int count)? onOnline;
  void Function(bool typing)? onTyping;
  void Function(bool connected)? onConnected;
  void Function()? onBanned;
  void Function(String text)? onNotice;
  void Function(String name, String country)? onPartner; // empty strings = no partner
  void Function()? onSearching; // looking for a stranger
  void Function(String name, String country, List<String> common)? onMatch;
  void Function()? onPartnerLeft; // the stranger skipped / disconnected

  /// STUN + short-lived TURN credentials come from the server (/api/ice).
  Future<void> _loadIce() async {
    try {
      final r = await http
          .get(Uri.parse('$kServerUrl/api/ice'))
          .timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        if (j['iceServers'] is List && (j['iceServers'] as List).isNotEmpty) {
          _ice = {'iceServers': j['iceServers']};
        }
      }
    } catch (_) {
      // keep the fallback STUN-only config
    }
  }

  Future<void> init() async {
    await _loadIce();
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    if (video) {
      try {
        _local = await navigator.mediaDevices
            .getUserMedia({'audio': kVoiceConstraints, 'video': true});
        localRenderer.srcObject = await videoOnlyPreview(_local!); // no self-playback = no echo
      } catch (_) {
        onStatus?.call('Camera/microphone permission denied.');
        return;
      }
    }

    socket = io.io(kServerUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });
    _ready = true;

    socket.on('online', (n) => onOnline?.call((n as num).toInt()));
    socket.on('waiting', (_) => onSearching?.call());
    socket.on('matched', (d) {
      final initiator = (d as Map)['initiator'] == true;
      final common = ((d['common'] as List?) ?? [])
          .map((e) => e.toString())
          .toList();
      final partner = d['partner'];
      final pName = partner is Map ? (partner['name']?.toString() ?? 'Anonymous') : 'Anonymous';
      final pCountry =
          partner is Map ? (partner['country']?.toString() ?? 'Unknown location') : 'Unknown location';
      partnerLanguage =
          partner is Map ? (partner['language']?.toString() ?? kAnyLang) : kAnyLang;
      onPartner?.call(pName, pCountry);
      onMatch?.call(pName, pCountry, common);
      onConnected?.call(true);
      _pcReady = _createPc();
      if (initiator && video) {
        _chain = _chain.then((_) async {
          await _pcReady;
          final offer = await _pc!.createOffer();
          final tuned = RTCSessionDescription(tuneOpus(offer.sdp), 'offer');
          await _pc!.setLocalDescription(tuned);
          socket.emit('signal', {'type': 'offer', 'sdp': tuned.sdp});
        });
      }
    });
    socket.on('signal', (d) {
      _chain = _chain.then((_) => _handleSignal(Map<String, dynamic>.from(d)));
    });
    socket.on('chat', (m) => onMessage?.call(m.toString(), false));
    socket.on('typing', (v) => onTyping?.call(v == true));
    socket.on('partner_left', (_) {
      _closePc();
      onPartner?.call('', '');
      onTyping?.call(false);
      onConnected?.call(false);
      onPartnerLeft?.call();
    });
    socket.on('banned', (_) => onBanned?.call());
    socket.on('notice', (m) => onNotice?.call(m.toString()));
    socket.onDisconnect((_) {
      _closePc();
      onConnected?.call(false);
      onTyping?.call(false);
      onStatus?.call('Connection lost. Reconnecting...');
    });
    socket.onConnect((_) => findNew());
    socket.connect();
  }

  Future<void> _createPc() async {
    await _closePc();
    if (!video) return;
    final pc = await createPeerConnection(_ice);
    _pc = pc;
    for (final t in _local?.getTracks() ?? <MediaStreamTrack>[]) {
      await pc.addTrack(t, _local!);
    }
    pc.onTrack = (e) {
      if (e.streams.isNotEmpty) remoteRenderer.srcObject = e.streams[0];
    };
    pc.onIceCandidate = (c) {
      if (c.candidate != null) {
        socket.emit('signal', {
          'type': 'candidate',
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      }
    };
  }

  Future<void> _handleSignal(Map<String, dynamic> d) async {
    await _pcReady;
    final pc = _pc;
    if (pc == null) return;
    switch (d['type']) {
      case 'offer':
        await pc.setRemoteDescription(RTCSessionDescription(d['sdp'], 'offer'));
        final answer = await pc.createAnswer();
        final tunedAns = RTCSessionDescription(tuneOpus(answer.sdp), 'answer');
        await pc.setLocalDescription(tunedAns);
        socket.emit('signal', {'type': 'answer', 'sdp': tunedAns.sdp});
        break;
      case 'answer':
        await pc.setRemoteDescription(RTCSessionDescription(d['sdp'], 'answer'));
        break;
      case 'candidate':
        await pc.addCandidate(
            RTCIceCandidate(d['candidate'], d['sdpMid'], d['sdpMLineIndex']));
        break;
    }
  }

  Future<void> _closePc() async {
    remoteRenderer.srcObject = null;
    await _pc?.close();
    _pc = null;
  }

  void findNew() {
    if (!_ready) return;
    onPartner?.call('', '');
    _closePc();
    onConnected?.call(false);
    onSearching?.call();
    socket.emit('find', {
      'interests': interests,
      'username': username,
      'language': language,
      'mode': video ? 'video' : 'text', // video only meets video, text only meets text
    });
  }

  /// Nobody speaks your language right now: search again with any language.
  void matchAnyLanguage() {
    language = kAnyLang;
    findNew();
  }

  /// "Stop": leave the current chat (or stop searching) without starting a new search.
  void stop() {
    if (!_ready) return;
    socket.emit('leave');
    _closePc();
    onPartner?.call('', '');
    onTyping?.call(false);
    onConnected?.call(false);
  }

  void send(String text) {
    if (!_ready) return;
    socket.emit('chat', text);
    onMessage?.call(text, true);
  }

  void typing(bool v) {
    if (_ready) socket.emit('typing', v);
  }
  void report(String reason) {
    if (_ready) socket.emit('report', {'reason': reason});
  }

  void toggleMic() {
    for (final t in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !t.enabled;
    }
  }

  void toggleCam() {
    for (final t in _local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !t.enabled;
    }
  }

  Future<void> dispose() async {
    if (_ready) {
      socket.emit('leave');
      socket.dispose();
    }
    await _closePc();
    for (final t in _local?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    await localRenderer.dispose();
    await remoteRenderer.dispose();
  }
}
