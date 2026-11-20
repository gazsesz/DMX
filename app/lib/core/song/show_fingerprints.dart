import 'dart:io';
import 'dart:isolate';

import '../../models/song_show.dart';
import 'audio_probe.dart';
import 'fingerprint.dart';

/// The fingerprint index of every song file the song shows play, for
/// recognising them through the microphone.
class ShowFingerprints {
  /// The song file path of each song in [index], in index order.
  final List<String> paths;
  final FingerprintIndex index;

  const ShowFingerprints(this.paths, this.index);
}

/// Landmarks already worked out, by file path and length — decoding and
/// fingerprinting a song takes a moment, and Song watch is switched on and
/// off far more often than the files change.
final Map<String, List<int>> _cache = {};

/// The song files [shows] link to (shows with cues only, each file once)
/// whose file is on this device.
List<String> recognisableSongPaths(List<SongShow> shows) {
  final paths = <String>[];
  for (final show in shows) {
    final path = show.audio?.path;
    if (path == null || show.cues.isEmpty || paths.contains(path)) continue;
    if (File(path).existsSync()) paths.add(path);
  }
  return paths;
}

/// Decodes and fingerprints the song files of [shows] (off the UI thread)
/// into one index. A file that can't be read is skipped.
Future<ShowFingerprints> buildShowFingerprints(List<SongShow> shows) async {
  final paths = <String>[];
  final landmarks = <List<int>>[];
  for (final path in recognisableSongPaths(shows)) {
    final durationMs = shows.firstWhere((s) => s.audio?.path == path).audio!.durationMs;
    final key = '$path|$durationMs';
    var marks = _cache[key];
    if (marks == null) {
      try {
        final samples = await readAnalysisSamples(path, Duration(milliseconds: durationMs));
        final computed = await Isolate.run(() => fingerprintLandmarks(samples));
        _cache[key] = computed;
        marks = computed;
      } catch (_) {
        continue;
      }
    }
    paths.add(path);
    landmarks.add(marks);
  }
  final index = await Isolate.run(() => FingerprintIndex.fromLandmarks(landmarks));
  return ShowFingerprints(paths, index);
}
