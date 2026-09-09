import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/beat_detector.dart';

/// One shared beat detector for the whole app, so a chase started from any
/// screen reacts to the same microphone listener the Dashboard toggles.
final beatDetectorProvider = Provider<BeatDetectorService>((ref) {
  final service = BeatDetectorService();
  ref.onDispose(service.dispose);
  return service;
});

/// Whether mic beat-sync is armed, shared by every screen that can start
/// playback. It has to be one flag: a bank fired from the Dashboard used to
/// pick up the Dashboard's own toggle, so a bank run from the Banks tab
/// could sit frozen waiting for beats with no way to switch it off from
/// there.
final beatSyncEnabledProvider = StateNotifierProvider<BeatSyncNotifier, bool>((ref) {
  return BeatSyncNotifier(ref.watch(beatDetectorProvider));
});

class BeatSyncNotifier extends StateNotifier<bool> {
  final BeatDetectorService _service;

  BeatSyncNotifier(this._service) : super(_service.isListening);

  /// Turns beat sync on/off, starting or stopping the microphone with it.
  /// Returns null on success, or the reason the mic couldn't be opened.
  Future<String?> setEnabled(bool value) async {
    if (!value) {
      await _service.stop();
      state = false;
      return null;
    }
    final started = await _service.start();
    if (!started) return _service.lastError ?? 'Could not start the microphone';
    state = true;
    return null;
  }
}
