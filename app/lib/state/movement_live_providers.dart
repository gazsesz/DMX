import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/movement_fx.dart';

/// The live Size / Speed / Shift / Smooth knobs over the running Movement FX.
///
/// Not saved with the project or the app: they're performance knobs, and a
/// show that opens with the heads at half size because of last night's set
/// would be a surprise. Every running effect reads them on each tick.
final movementLiveProvider = StateNotifierProvider<MovementLiveNotifier, MovementLive>(
  (ref) => MovementLiveNotifier(),
);

class MovementLiveNotifier extends StateNotifier<MovementLive> {
  MovementLiveNotifier() : super(MovementLive.neutral);

  void set({double? size, double? speed, double? shift, double? smooth}) {
    state = state.copyWith(size: size, speed: speed, shift: shift, smooth: smooth);
  }

  void reset() => state = MovementLive.neutral;
}
