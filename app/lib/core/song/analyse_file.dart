import 'dart:isolate';

import 'audio_probe.dart';
import 'song_analysis.dart';

/// Decodes [path] and analyses it off the UI thread. Throws when the file
/// can't be read.
Future<SongAnalysis> analyseAudioFile(String path) async {
  final probe = await probeAudio(path);
  final samples = await readAnalysisSamples(path, probe.length);
  return Isolate.run(() => analyzeSong(samples, analysisSampleRate));
}
