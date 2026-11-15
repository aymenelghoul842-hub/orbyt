import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config.dart';
import 'audio_tune.dart';

/// One live on the list.
class LiveInfo {
  LiveInfo({
    required this.id,
    required this.title,
    required this.name,
    required this.country,
    required this.countryCode,
    required this.viewers,
    required this.since,
  });
  final String id, title, name, country, countryCode;
  final int viewers;
  final int since;

  factory LiveInfo.fromJson(Map<String, dynamic> j) => LiveInfo(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? 'Live',
        name: j['name']?.toString() ?? 'Anonymous',
        country: j['country']?.toString() ?? '',
        countryCode: j['countryCode']?.toString() ?? '',
        viewers: (j['viewers'] as num?)?.toInt() ?? 0,
        since: (j['since'] as num?)?.toInt() ?? 0,
      );
}

/// Whoever is watching confirmed they are 18+ (kept in memory for this visit).
bool liveAgeConfirmed = false;

/// Fetch everybody who is live right now. Returns an empty list on any error.
Future<List<LiveInfo>> fetchLives() async {
  try {
    final r = await http
        .get(Uri.parse('$kServerUrl/api/lives'))
        .timeout(const Duration(seconds: 5));
    if (r.statusCode != 200) return const [];
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return ((j['lives'] as List?) ?? const [])
        .map((e) => LiveInfo.fromJson(Map<String, dynamic>.from(e as Map)))
        .where((l) => l.id.isNotEmpty)
        .toList();
  } catch (_) {
    return const [];
  }
}

class LiveComment {
  LiveComment(this.sid, this.name, this.text, this.host);
  final String sid, name, text;
  final bool host;
}

/// A viewer who was invited on stage (audio or camera).
class GuestInfo {
  GuestInfo(this.sid, this.name, this.video, this.streamId, [this.muted = false]);
  final String sid, name, streamId;
  final bool video, muted;
}

/// A person watching (host only sees this list).
class ViewerInfo {
  ViewerInfo(this.sid, this.name, this.guest, this.invited);
  final String sid, name;
  final bool guest, invited;
}

/// Host (broadcasts camera + mic) or viewer (watches + comments).
/// Video travels host -> viewer over WebRTC; the server only relays signalling and comments.
class LiveService {
  LiveService.host({this.title = '', this.username})
      : isHost = true,
        liveId = '';
  LiveService.viewer({required this.liveId, this.username})
      : isHost = false,
        title = '';

  final bool isHost;
  final String liveId;
  final String title;
  final String? username;

  late final io.Socket socket;
  bool _ready = false;
  bool _disposed = false;
  Map<String, dynamic> _ice = kIceConfig;
  MediaStream? _local;
  final Map<String, RTCPeerConnection> _peers = {}; // host: one per viewer; viewer: just the host
  Future<void> _chain = Future.value();

  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();

  // ---- guests on stage
  // The guest sends camera/mic to the HOST (channel "up"); the host relays it to every other viewer.
  List<GuestInfo> guests = [];
  List<ViewerInfo> viewerList = []; // host only
  final Map<String, RTCVideoRenderer> guestRenderers = {}; // guest sid -> picture/sound
  final Map<String, RTCPeerConnection> _upPeers = {}; // host: guest sid -> peer
  final Map<String, MediaStream> _guestStreams = {}; // host: guest sid -> stream received
  final Map<String, MediaStream> _remoteStreams = {}; // viewer: stream id -> stream
  Timer? _relayTimer;
  RTCPeerConnection? _upPc; // guest: the connection that sends me to the host
  MediaStream? _guestLocal;
  String _hostSid = '';
  String cameraProblem = ''; // human text when the camera/mic could not start
  final Set<String> _creating = {}; // renderers being created (avoids duplicates = double sound)
  bool isGuest = false;
  bool hostMuted = false; // the host muted my microphone
  bool guestVideo = false;
  String get mySid => _ready ? (socket.id ?? '') : '';

  // Info shown on screen.
  String liveTitle = '';
  String hostName = '';
  String hostCountry = '';
  int viewers = 0;

  void Function()? onInfo; // title / name / country changed
  void Function(String status)? onStatus; // connection text
  void Function(int count)? onCount;
  void Function(LiveComment c)? onComment;
  void Function()? onVideo; // viewer: video started arriving
  void Function(String reason)? onEnded; // 'ended' | 'kicked' | 'banned'
  void Function(String code)? onError; // adult_required | not_found | full | kicked | busy | rate | camera
  void Function(String text)? onNotice;
  void Function()? onGuests; // guest tiles changed
  void Function()? onViewers; // host: the viewers list changed
  void Function(bool video, String host)? onInvite; // viewer: the host invites me on stage
  void Function(String state)? onGuestState; // 'guest' | 'left' | 'removed' | 'full'

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
    if (isHost) {
      // Try the best settings first, then simpler ones: some cameras/browsers refuse fancy settings.
      final attempts = <Map<String, dynamic>>[
        {'audio': kVoiceConstraints, 'video': true},
        {'audio': true, 'video': true},
        {'audio': false, 'video': true}, // no microphone found: still go live with the camera
      ];
      Object? lastErr;
      for (final c in attempts) {
        try {
          _local = await navigator.mediaDevices.getUserMedia(c);
          break;
        } catch (e) {
          lastErr = e;
        }
      }
      if (_local == null) {
        final t = '$lastErr';
        cameraProblem = t.contains('NotAllowed') || t.contains('Permission')
            ? 'Camera/microphone permission was denied. Allow them in your browser (lock icon next to the address), then try again.'
            : t.contains('NotFound') || t.contains('DevicesNotFound')
                ? 'No camera was found on this device.'
                : t.contains('NotReadable') || t.contains('Abort') || t.contains('TrackStart')
                    ? 'Your camera is being used by another app or tab. Close it and try again.'
                    : 'The camera could not start ($t).';
        onError?.call('camera');
        return;
      }
      try {
        localRenderer.srcObject = await videoOnlyPreview(_local!); // no self-playback = no echo
      } catch (_) {
        localRenderer.srcObject = _local; // local streams are muted by the renderer anyway
      }
    }

    socket = io.io(kServerUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });
    _ready = true;

    socket.on('live_started', (d) {
      onStatus?.call('');
    });
    socket.on('live_joined', (d) {
      final m = Map<String, dynamic>.from(d as Map);
      liveTitle = m['title']?.toString() ?? '';
      hostName = m['name']?.toString() ?? '';
      hostCountry = m['country']?.toString() ?? '';
      viewers = (m['viewers'] as num?)?.toInt() ?? 0;
      onInfo?.call();
      onCount?.call(viewers);
      onStatus?.call('Connecting to the live...');
    });
    socket.on('live_count', (n) {
      viewers = (n as num).toInt();
      onCount?.call(viewers);
    });
    // host: a viewer arrived -> send them the video
    socket.on('live_viewer', (d) {
      final vid = Map<String, dynamic>.from(d as Map)['vid'].toString();
      _chain = _chain.then((_) => _offerTo(vid)).catchError((_) {});
    });
    socket.on('live_viewer_left', (d) {
      final vid = Map<String, dynamic>.from(d as Map)['vid'].toString();
      final pc = _peers.remove(vid);
      pc?.close();
      _dropGuest(vid);
    });
    socket.on('live_signal', (d) {
      final m = Map<String, dynamic>.from(d as Map);
      _chain = _chain.then((_) => _handleSignal(m)).catchError((_) {});
    });
    socket.on('live_chat', (d) {
      final m = Map<String, dynamic>.from(d as Map);
      onComment?.call(LiveComment(
        m['sid']?.toString() ?? '',
        m['name']?.toString() ?? 'Anonymous',
        m['text']?.toString() ?? '',
        m['host'] == true,
      ));
    });
    socket.on('live_guests', (d) {
      guests = ((d as List?) ?? const []).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return GuestInfo(m['sid']?.toString() ?? '', m['name']?.toString() ?? 'Anonymous',
            m['video'] == true, m['streamId']?.toString() ?? '', m['muted'] == true);
      }).toList();
      if (!isHost) _remap();
      onGuests?.call();
    });
    socket.on('live_viewers', (d) {
      viewerList = ((d as List?) ?? const []).map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return ViewerInfo(m['sid']?.toString() ?? '', m['name']?.toString() ?? 'Anonymous',
            m['guest'] == true, m['invited'] == true);
      }).toList();
      onViewers?.call();
    });
    socket.on('live_guest_left', (d) {
      final sid = Map<String, dynamic>.from(d as Map)['sid'].toString();
      _dropGuest(sid);
    });
    socket.on('live_invited', (d) {
      final m = Map<String, dynamic>.from(d as Map);
      if (!isHost && !isGuest) onInvite?.call(m['video'] == true, m['host']?.toString() ?? '');
    });
    socket.on('live_mute_by_host', (d) {
      hostMuted = Map<String, dynamic>.from(d as Map)['muted'] == true;
      for (final t in _guestLocal?.getAudioTracks() ?? <MediaStreamTrack>[]) {
        t.enabled = !hostMuted;
      }
      onGuestState?.call(hostMuted ? 'muted' : 'unmuted');
    });
    socket.on('live_invite_cancelled', (_) => onGuestState?.call('cancelled'));
    socket.on('live_guest_ok', (d) => _publish(Map<String, dynamic>.from(d as Map)));
    socket.on('live_guest_removed', (d) {
      _stopGuest();
      onGuestState?.call(d?.toString() ?? 'removed');
    });
    socket.on('live_ended', (_) => onEnded?.call('ended'));
    socket.on('live_kicked', (_) => onEnded?.call('kicked'));
    socket.on('live_error', (c) => onError?.call(c.toString()));
    socket.on('banned', (_) => onEnded?.call('banned'));
    socket.on('notice', (m) => onNotice?.call(m.toString()));
    socket.onDisconnect((_) {
      if (!_disposed) onStatus?.call('Connection lost...');
    });
    socket.onConnect((_) {
      if (isHost) {
        socket.emit('live_start',
            {'title': title, 'username': username, 'adult': true});
      } else {
        socket.emit('live_join',
            {'id': liveId, 'username': username, 'adult': true});
      }
    });
    socket.connect();
  }

  // ---- host: one peer connection per viewer
  Future<void> _offerTo(String vid) async {
    final old = _peers.remove(vid);
    await old?.close();
    final pc = await createPeerConnection(_ice);
    _peers[vid] = pc;
    for (final t in _local?.getTracks() ?? <MediaStreamTrack>[]) {
      await pc.addTrack(t, _local!);
    }
    // relay the guests on stage (everybody except the guest themself, no echo)
    for (final e in _guestStreams.entries) {
      if (e.key == vid) continue;
      for (final t in e.value.getTracks()) {
        await pc.addTrack(t, e.value);
      }
    }
    pc.onIceCandidate = (c) {
      if (c.candidate != null) {
        socket.emit('live_signal', {
          'to': vid,
          'type': 'candidate',
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      }
    };
    final offer = await pc.createOffer();
    final tuned = RTCSessionDescription(tuneOpus(offer.sdp), 'offer');
    await pc.setLocalDescription(tuned);
    socket.emit('live_signal', {'to': vid, 'type': 'offer', 'sdp': tuned.sdp});
  }

  Future<void> _handleSignal(Map<String, dynamic> d) async {
    final from = d['from']?.toString() ?? '';
    if (from.isEmpty) return;
    if (d['ch'] == 'up') return _handleUp(from, d);
    switch (d['type']) {
      case 'offer': // viewer receives the host's offer
        if (isHost) return;
        _hostSid = from;
        final old = _peers.remove(from);
        await old?.close();
        _remoteStreams.clear(); // the host re-sends everything (guests changed)
        final pc = await createPeerConnection(_ice);
        _peers[from] = pc;
        pc.onTrack = (e) {
          if (e.streams.isNotEmpty) {
            _remoteStreams[e.streams[0].id] = e.streams[0];
            _remap();
            onVideo?.call();
          }
        };
        pc.onIceCandidate = (c) {
          if (c.candidate != null) {
            socket.emit('live_signal', {
              'to': from,
              'type': 'candidate',
              'candidate': c.candidate,
              'sdpMid': c.sdpMid,
              'sdpMLineIndex': c.sdpMLineIndex,
            });
          }
        };
        await pc.setRemoteDescription(RTCSessionDescription(d['sdp'], 'offer'));
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        socket.emit(
            'live_signal', {'to': from, 'type': 'answer', 'sdp': answer.sdp});
        break;
      case 'answer': // host receives a viewer's answer
        final pc = _peers[from];
        if (pc == null) return;
        await pc.setRemoteDescription(RTCSessionDescription(d['sdp'], 'answer'));
        break;
      case 'candidate':
        final pc = _peers[from];
        if (pc == null) return;
        await pc.addCandidate(
            RTCIceCandidate(d['candidate'], d['sdpMid'], d['sdpMLineIndex']));
        break;
    }
  }

  // ---- the "up" channel: guest -> host
  Future<void> _handleUp(String from, Map<String, dynamic> d) async {
    if (isHost) {
      switch (d['type']) {
        case 'offer': // a guest starts sending me their camera/mic
          final old = _upPeers.remove(from);
          await old?.close();
          final pc = await createPeerConnection(_ice);
          _upPeers[from] = pc;
          pc.onTrack = (e) {
            if (e.streams.isNotEmpty) _onGuestTrack(from, e.streams[0]);
          };
          pc.onIceCandidate = (c) {
            if (c.candidate != null) {
              socket.emit('live_signal', {
                'to': from,
                'ch': 'up',
                'type': 'candidate',
                'candidate': c.candidate,
                'sdpMid': c.sdpMid,
                'sdpMLineIndex': c.sdpMLineIndex,
              });
            }
          };
          await pc.setRemoteDescription(RTCSessionDescription(d['sdp'], 'offer'));
          final answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);
          socket.emit('live_signal',
              {'to': from, 'ch': 'up', 'type': 'answer', 'sdp': answer.sdp});
          break;
        case 'candidate':
          await _upPeers[from]?.addCandidate(
              RTCIceCandidate(d['candidate'], d['sdpMid'], d['sdpMLineIndex']));
          break;
      }
    } else {
      switch (d['type']) {
        case 'answer': // host accepted my media
          await _upPc?.setRemoteDescription(RTCSessionDescription(d['sdp'], 'answer'));
          break;
        case 'candidate':
          await _upPc?.addCandidate(
              RTCIceCandidate(d['candidate'], d['sdpMid'], d['sdpMLineIndex']));
          break;
      }
    }
  }

  // host: a guest's media arrived -> show it, tell viewers which stream is whose, relay it
  void _onGuestTrack(String sid, MediaStream st) {
    _guestStreams[sid] = st;
    () async {
      var r = guestRenderers[sid];
      if (r == null) {
        // audio and video tracks arrive one after the other: create the renderer only once
        if (!_creating.add(sid)) return;
        r = RTCVideoRenderer();
        await r.initialize();
        _creating.remove(sid);
        if (!_guestStreams.containsKey(sid)) {
          await r.dispose();
          return;
        }
        guestRenderers[sid] = r;
      }
      r.srcObject = _guestStreams[sid];
      onGuests?.call();
    }();
    socket.emit('live_guest_stream', {'sid': sid, 'streamId': st.id});
    _relayTimer?.cancel(); // wait until audio + video both arrived
    _relayTimer = Timer(const Duration(milliseconds: 700), _relayAll);
  }

  // host: rebuild every viewer's connection so it carries the current guests
  void _relayAll() {
    if (_disposed) return;
    for (final vid in _peers.keys.toList()) {
      _chain = _chain.then((_) => _offerTo(vid)).catchError((_) {});
    }
  }

  void _dropGuest(String sid) {
    if (!isHost) return;
    final had = _guestStreams.remove(sid) != null || _upPeers.containsKey(sid);
    final up = _upPeers.remove(sid);
    up?.close();
    final r = guestRenderers.remove(sid);
    onGuests?.call();
    if (r != null) {
      Future.delayed(const Duration(milliseconds: 600), () async {
        r.srcObject = null;
        await r.dispose();
      });
    }
    if (had) _relayAll();
  }

  // viewer: decide which received stream is the host and which are guests
  void _remap() {
    final guestIds = {for (final g in guests) if (g.streamId.isNotEmpty) g.streamId};
    // main picture = first stream that is not a guest
    for (final e in _remoteStreams.entries) {
      if (!guestIds.contains(e.key)) {
        if (!identical(remoteRenderer.srcObject, e.value)) remoteRenderer.srcObject = e.value;
        break;
      }
    }
    for (final g in guests) {
      if (g.sid == mySid) continue;
      final st = _remoteStreams[g.streamId];
      if (st == null) continue;
      final existing = guestRenderers[g.sid];
      if (existing != null) {
        if (!identical(existing.srcObject, st)) existing.srcObject = st;
      } else {
        if (!_creating.add(g.sid)) continue; // already being created
        () async {
          final r = RTCVideoRenderer();
          await r.initialize();
          _creating.remove(g.sid);
          if (!guests.any((x) => x.sid == g.sid)) {
            await r.dispose();
            return;
          }
          r.srcObject = _remoteStreams[g.streamId] ?? st;
          guestRenderers[g.sid] = r;
          onGuests?.call();
        }();
      }
    }
    // drop renderers of guests who left
    for (final sid in guestRenderers.keys.toList()) {
      if (!guests.any((g) => g.sid == sid)) {
        final r = guestRenderers.remove(sid)!;
        Future.delayed(const Duration(milliseconds: 600), () async {
          r.srcObject = null;
          await r.dispose();
        });
      }
    }
  }

  // ---- viewer: join the stage
  /// Called after the viewer accepted an invite: ask for mic/camera, then tell the server.
  Future<bool> acceptInvite(bool video) async {
    try {
      _guestLocal = await navigator.mediaDevices
          .getUserMedia({'audio': kVoiceConstraints, 'video': video});
    } catch (_) {
      socket.emit('live_decline');
      onNotice?.call('Camera/microphone permission was denied.');
      return false;
    }
    guestVideo = video;
    socket.emit('live_accept');
    return true;
  }

  void declineInvite() {
    if (_ready) socket.emit('live_decline');
  }

  Future<void> _publish(Map<String, dynamic> m) async {
    final local = _guestLocal;
    if (local == null || _hostSid.isEmpty) {
      socket.emit('live_guest_leave');
      return;
    }
    isGuest = true;
    guestVideo = m['video'] == true;
    if (guestVideo) localRenderer.srcObject = await videoOnlyPreview(local);
    final pc = await createPeerConnection(_ice);
    _upPc = pc;
    for (final t in local.getTracks()) {
      await pc.addTrack(t, local);
    }
    pc.onIceCandidate = (c) {
      if (c.candidate != null) {
        socket.emit('live_signal', {
          'to': _hostSid,
          'ch': 'up',
          'type': 'candidate',
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      }
    };
    final offer = await pc.createOffer();
    final tuned = RTCSessionDescription(tuneOpus(offer.sdp), 'offer');
    await pc.setLocalDescription(tuned);
    socket.emit('live_signal',
        {'to': _hostSid, 'ch': 'up', 'type': 'offer', 'sdp': tuned.sdp});
    onGuestState?.call('guest');
  }

  void _stopGuest() {
    isGuest = false;
    hostMuted = false;
    _upPc?.close();
    _upPc = null;
    for (final t in _guestLocal?.getTracks() ?? <MediaStreamTrack>[]) {
      t.stop();
    }
    _guestLocal = null;
    if (!isHost) localRenderer.srcObject = null;
  }

  void leaveStage() {
    if (_ready && isGuest) socket.emit('live_guest_leave');
  }

  // ---- host controls
  void invite(String sid, bool video) {
    if (_ready && isHost) socket.emit('live_invite', {'sid': sid, 'video': video});
  }

  void cancelInvite(String sid) {
    if (_ready && isHost) socket.emit('live_invite_cancel', {'sid': sid});
  }

  void muteGuest(String sid, bool muted) {
    if (_ready && isHost) socket.emit('live_guest_mute', {'sid': sid, 'muted': muted});
  }

  void removeGuest(String sid) {
    if (_ready && isHost) socket.emit('live_guest_remove', {'sid': sid});
  }

  void comment(String text) {
    if (_ready && text.trim().isNotEmpty) socket.emit('live_chat', text.trim());
  }

  void report(String reason) {
    if (_ready && !isHost) socket.emit('live_report', {'reason': reason});
  }

  void kick(String sid) {
    if (_ready && isHost) socket.emit('live_kick', {'sid': sid});
  }

  MediaStream? get _mine => isHost ? _local : _guestLocal;

  void toggleMic() {
    if (!isHost && hostMuted) {
      onNotice?.call('The host muted you.');
      return;
    }
    for (final t in _mine?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !t.enabled;
    }
  }

  void toggleCam() {
    for (final t in _mine?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !t.enabled;
    }
  }

  bool get micOn =>
      (_mine?.getAudioTracks() ?? <MediaStreamTrack>[]).any((t) => t.enabled);
  bool get camOn =>
      (_mine?.getVideoTracks() ?? <MediaStreamTrack>[]).any((t) => t.enabled);

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_ready) {
      socket.emit(isHost ? 'live_end' : 'live_leave');
      socket.dispose();
    }
    for (final pc in _peers.values) {
      await pc.close();
    }
    _peers.clear();
    _relayTimer?.cancel();
    for (final pc in _upPeers.values) {
      await pc.close();
    }
    _upPeers.clear();
    await _upPc?.close();
    for (final t in _guestLocal?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    for (final r in guestRenderers.values) {
      r.srcObject = null;
      await r.dispose();
    }
    guestRenderers.clear();
    for (final t in _local?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    await localRenderer.dispose();
    await remoteRenderer.dispose();
  }
}
