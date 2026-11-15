import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Microphone settings for a clean voice: no echo, no background hiss, steady volume.
const Map<String, dynamic> kVoiceConstraints = {
  'echoCancellation': true,
  'noiseSuppression': true,
  'autoGainControl': true,
  'channelCount': 1,
};

/// Make Opus (the voice codec) tougher against packet loss, which is what causes
/// the crackling / "robot" voice: forward error correction on, mono, 48 kbps, no DTX.
String tuneOpus(String? sdp) {
  if (sdp == null) return '';
  final m = RegExp(r'a=rtpmap:(\d+) opus/48000/2').firstMatch(sdp);
  if (m == null) return sdp;
  final pt = m.group(1)!;
  const extra =
      'minptime=10;useinbandfec=1;usedtx=0;stereo=0;sprop-stereo=0;maxaveragebitrate=48000;maxplaybackrate=48000';
  final fmtp = RegExp('a=fmtp:$pt ([^\\r\\n]*)');
  if (fmtp.hasMatch(sdp)) {
    return sdp.replaceFirstMapped(fmtp, (f) {
      final kept = f
          .group(1)!
          .split(';')
          .where((p) => p.isNotEmpty && !RegExp(
                  r'^(minptime|useinbandfec|usedtx|stereo|sprop-stereo|maxaveragebitrate|maxplaybackrate)=')
              .hasMatch(p))
          .toList();
      return 'a=fmtp:$pt ${[...kept, extra].join(';')}';
    });
  }
  return sdp.replaceFirst(m.group(0)!, '${m.group(0)!}\r\na=fmtp:$pt $extra');
}

/// A video-only copy of a stream, for the self-view. Playing your own microphone through
/// your own speakers is what makes the echo / "parasite" noise, so the preview never has audio.
Future<MediaStream> videoOnlyPreview(MediaStream src) async {
  final preview = await createLocalMediaStream('preview');
  for (final t in src.getVideoTracks()) {
    await preview.addTrack(t);
  }
  return preview;
}
