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
