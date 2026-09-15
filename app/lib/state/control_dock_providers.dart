import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/control_dock_prefs.dart';

const prefDockExpanded = 'dock.expanded';
const prefDockPosition = 'dock.position';
const prefStageVisible = 'dock.stageVisible';

class ControlDockState {
  /// The dock's panel is open, showing the tempo and beat controls.
  ///
  /// The dock *strip* itself is always on screen and has no hide switch any
  /// more: it's the only place the tempo lives now, and a control you can
  /// lose is worse than 74 pixels of edge.
  final bool expanded;

  final ControlDockPosition position;

  /// The 2D Live Stage strip. Always along the bottom — it needs the width
  /// to be readable, so it doesn't get the dock's side option.
  final bool stageVisible;

  const ControlDockState({
    this.expanded = false,
    this.position = ControlDockPosition.bottom,
    this.stageVisible = false,
  });

  ControlDockState copyWith({bool? expanded, ControlDockPosition? position, bool? stageVisible}) {
    return ControlDockState(
      expanded: expanded ?? this.expanded,
      position: position ?? this.position,
      stageVisible: stageVisible ?? this.stageVisible,
    );
  }
}

/// Whether the control dock's panel is open, and which edge the dock sits
/// on. Persisted like the other app-level preferences (loaded before the
/// first frame in `main()`), so it comes back the way it was left.
class ControlDockNotifier extends StateNotifier<ControlDockState> {
  ControlDockNotifier(super.initial);

  void toggleExpanded() => _set(state.copyWith(expanded: !state.expanded));

  void collapse() {
    if (state.expanded) _set(state.copyWith(expanded: false));
  }

  void toggleStageVisible() => _set(state.copyWith(stageVisible: !state.stageVisible));

  void setPosition(ControlDockPosition position) => _set(state.copyWith(position: position));

  void _set(ControlDockState next) {
    state = next;
    _persist(next);
  }

  Future<void> _persist(ControlDockState prefs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(prefDockExpanded, prefs.expanded);
    await sp.setString(prefDockPosition, prefs.position.name);
    await sp.setBool(prefStageVisible, prefs.stageVisible);
  }
}

final controlDockProvider = StateNotifierProvider<ControlDockNotifier, ControlDockState>((ref) {
  return ControlDockNotifier(const ControlDockState());
});

ControlDockState controlDockFromPrefs({bool? expanded, String? position, bool? stageVisible}) {
  return ControlDockState(
    expanded: expanded ?? false,
    position: ControlDockPosition.values.firstWhere(
      (e) => e.name == position,
      orElse: () => ControlDockPosition.bottom,
    ),
    stageVisible: stageVisible ?? false,
  );
}
