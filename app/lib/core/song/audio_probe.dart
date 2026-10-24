import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

/// What the editor needs to know about a song file before it can draw it.
class AudioProbe {
  final Duration length;

  /// Peak-ish envelope, [binsPerSecond] values per second, 0..1.
  final Float32List waveform;
  final int binsPerSecond;

  const AudioProbe({required this.length, required this.waveform, required this.binsPerSecond});
}

const waveformBinsPerSecond = 20;

/// Reads [path]'s length and a waveform envelope. Throws when the file can't
/// be decoded.
Future<AudioProbe> probeAudio(String path) async {
  final engine = SoLoud.instance;
  if (!engine.isInitialized) await engine.init();
  final source = await engine.loadFile(path, mode: LoadMode.disk);
  final length = engine.getLength(source);
  await engine.disposeSource(source);
  final bins = (length.inMilliseconds / 1000 * waveformBinsPerSecond).round().clamp(100, 40000);
  final wave = await engine.readSamplesFromFile(path, bins, average: true);
  return AudioProbe(length: length, waveform: wave, binsPerSecond: waveformBinsPerSecond);
}

/// The rate analysis works at: plenty for tempo and bass, and a 5-minute song
/// is only ~13 MB of floats.
const analysisSampleRate = 11025;

/// Real (signed) mono samples of [path] at [analysisSampleRate].
///
/// Read at twice the rate and averaged in pairs: asking the engine for fewer
/// samples just drops the rest, folding high frequencies into the low band,
/// while the pair average is a crude but real low-pass. (`average: true` on
/// the engine is something else — an absolute-value envelope, for waveforms.)
Future<Float32List> readAnalysisSamples(String path, Duration length) async {
  final engine = SoLoud.instance;
  if (!engine.isInitialized) await engine.init();
  final wanted = (length.inMilliseconds / 1000 * analysisSampleRate * 2).round();
  final raw = await engine.readSamplesFromFile(path, wanted);
  final out = Float32List(raw.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = (raw[2 * i] + raw[2 * i + 1]) / 2;
  }
  return out;
}
