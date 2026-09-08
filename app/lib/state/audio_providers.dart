import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/beat_detector.dart';

/// One shared beat detector for the whole app, so a chase started from any
/// screen reacts to the same microphone listener the Dashboard toggles.
final beatDetectorProvider = Provider<BeatDetectorService>((ref) {
  final service = BeatDetectorService();
  ref.onDispose(service.dispose);
  return service;
});
