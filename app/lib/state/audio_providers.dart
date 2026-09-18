import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/beat_detector.dart';
import '../core/audio/beat_predictor.dart';
import '../core/playback/chase_player.dart';

/// One shared beat detector for the whole app, so a chase started from any
/// screen reacts to the same microphone listener the Dashboard toggles.
final beatDetectorProvider = Provider<BeatDetectorService>((ref) {
  final service = BeatDetectorService();
  ref.onDispose(service.dispose);
  return service;
});

/// One shared predictor sitting in front of [beatDetectorProvider], so every
/// beat-synced chase (Dashboard, Banks, the Chase editor's preview) fills
/// the same missed beats the same way instead of each screen guessing on
/// its own.
final beatPredictorProvider = Provider<BeatPredictor>((ref) {
  final predictor = BeatPredictor(ref.watch(beatDetectorProvider).beatEvents);
  ref.onDispose(predictor.dispose);
  return predictor;
});

/// Whether the predictor is filling in missed beats. Off by default —
/// same reasoning as [beatSyncEnabledProvider] starting false: it's a
/// listening mode you opt into, not one that should surprise you by already
/// being on. Only meaningful (and only shown in the UI) while beat sync
/// itself is armed.
final beatPredictionEnabledProvider = StateNotifierProvider<BeatPredictionNotifier, bool>((ref) {
  return BeatPredictionNotifier(ref.watch(beatPredictorProvider));
});

class BeatPredictionNotifier extends StateNotifier<bool> {
  final BeatPredictor _predictor;

  BeatPredictionNotifier(this._predictor) : super(false);

  void setEnabled(bool value) {
    _predictor.enabled = value;
    state = value;
  }
}

/// Whether mic beat-sync is armed, shared by every screen that can start
/// playback. It has to be one flag: a bank fired from the Dashboard used to
/// pick up the Dashboard's own toggle, so a bank run from the Banks tab
/// could sit frozen waiting for beats with no way to switch it off from
/// there.
final beatSyncEnabledProvider = StateNotifierProvider<BeatSyncNotifier, bool>((ref) {
  return BeatSyncNotifier(ref.watch(beatDetectorProvider));
});

/// Half time / on the beat / double time / flash — shared app-wide like
/// [beatSyncEnabledProvider], so a chase reads the same however it's fired.
final beatRateProvider = StateProvider<BeatRate>((ref) => BeatRate.normal);

/// How long the lit step stays up in [BeatRate.flash].
///
/// 80 ms is about the shortest a flash still reads as light rather than a
/// glitch, and short enough that the rig is dark again well before the next
/// beat at any danceable tempo.
final flashLengthProvider = StateProvider<Duration>((ref) => const Duration(milliseconds: 80));

BeatRate beatRateOf(WidgetRef ref) => ref.read(beatRateProvider);

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
