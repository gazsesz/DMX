import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/control_dock_prefs.dart';

const prefDockVisible = 'dock.visible';
const prefDockPosition = 'dock.position';
const prefStageVisible = 'dock.stageVisible';

class ControlDockState {
  final bool visible;
  final ControlDockPosition position;

  /// The 2D Live Stage strip. Always along the bottom — it needs the width
  /// to be readable, so it doesn't get the dock's side option.
  final bool stageVisible;

  const ControlDockState({
    this.visible = false,
    this.position = ControlDockPosition.bottom,
    this.stageVisible = false,
  });

  ControlDockState copyWith({bool? visible, ControlDockPosition? position, bool? stageVisible}) {
    return ControlDockState(
      visible: visible ?? this.visible,
      position: position ?? this.position,
      stageVisible: stageVisible ?? this.stageVisible,
    );
  }
}

/// Whether the always-on-screen control dock is showing, and which edge it
/// sits on. Persisted like the other app-level preferences (loaded before
/// the first frame in `main()`), so it comes back the way it was left.
class ControlDockNotifier extends StateNotifier<ControlDockState> {
  ControlDockNotifier(super.initial);

  void toggleVisible() => _set(state.copyWith(visible: !state.visible));

  void toggleStageVisible() => _set(state.copyWith(stageVisible: !state.stageVisible));

  void setPosition(ControlDockPosition position) => _set(state.copyWith(position: position));

  void _set(ControlDockState next) {
    state = next;
    _persist(next);
  }

  Future<void> _persist(ControlDockState prefs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(prefDockVisible, prefs.visible);
    await sp.setString(prefDockPosition, prefs.position.name);
    await sp.setBool(prefStageVisible, prefs.stageVisible);
  }
}

final controlDockProvider = StateNotifierProvider<ControlDockNotifier, ControlDockState>((ref) {
  return ControlDockNotifier(const ControlDockState());
});

ControlDockState controlDockFromPrefs({bool? visible, String? position, bool? stageVisible}) {
  return ControlDockState(
    visible: visible ?? false,
    position: ControlDockPosition.values.firstWhere(
      (e) => e.name == position,
      orElse: () => ControlDockPosition.bottom,
    ),
    stageVisible: stageVisible ?? false,
  );
}
