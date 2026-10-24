import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback/color_override.dart';
import '../core/artnet/artnet_service.dart';
import 'artnet_providers.dart';
import 'fixture_group_providers.dart';
import 'fixture_providers.dart';

export '../core/playback/color_override.dart' show LiveColor, liveColors, liveColorFromHex, liveColorNamed;

/// What the live Colour strip is doing right now.
class LiveColorState {
  /// The colour laid over the show, or null for "Auto" — the scenes' own.
  final LiveColor? color;

  /// A saved fixture group the colour is limited to, or null for every fixture.
  final String? groupId;

  const LiveColorState({this.color, this.groupId});

  bool get active => color != null;
}

/// The live Colour strip: a basic colour laid over the colour channels of the
/// whole rig, or of one saved group, on top of whatever the scenes play.
///
/// Like the Movement knobs it is a performance control, not part of the show:
/// not saved with the project or the app, and it stays on across scene and
/// bank changes until it is set back to Auto.
final liveColorProvider = StateNotifierProvider<LiveColorController, LiveColorState>((ref) {
  return LiveColorController(ref);
});

class LiveColorController extends StateNotifier<LiveColorState> {
  final Ref _ref;
  final ArtNetService _service;
  Map<String, List<FixtureColorPatch>> _patches = const {};

  LiveColorController(this._ref) : _service = _ref.read(artNetServiceProvider), super(const LiveColorState()) {
    // A re-patch moves channels around; the patches are worked out against
    // the old one.
    _ref.listen(patchedFixturesProvider, (_, _) => _rebuild());
    _ref.listen(fixtureGroupsProvider, (_, _) {
      if (state.groupId != null) _rebuild();
    });
  }

  /// Lays [color] over the show; [groupId] limits it to one saved group.
  void set(LiveColor color, {String? groupId}) {
    state = LiveColorState(color: color, groupId: groupId);
    _rebuild();
  }

  /// Back to the scenes' own colours.
  void auto() {
    if (!state.active) return;
    state = const LiveColorState();
    _rebuild();
  }

  /// Picks the group the colour applies to, keeping the colour.
  void setGroup(String? groupId) {
    state = LiveColorState(color: state.color, groupId: groupId);
    if (state.active) _rebuild();
  }

  void _rebuild() {
    final service = _service;
    final color = state.color;
    if (color == null) {
      _patches = const {};
      service.colorOverride = null;
      return;
    }
    Set<String>? only;
    final groupId = state.groupId;
    if (groupId != null) {
      for (final group in _ref.read(fixtureGroupsProvider)) {
        if (group.id == groupId) only = group.fixtureIds.toSet();
      }
      // A group deleted under us: fall back to the whole rig.
    }
    _patches = colorPatchesFor(
      _ref.read(patchedFixturesProvider),
      _ref.read(universesProvider),
      color,
      only: only,
    );
    service.colorOverride = (universe, frame) {
      final patches = _patches[universe.id];
      return patches == null ? frame : applyColorOverride(frame, patches, color);
    };
  }

  @override
  void dispose() {
    _service.colorOverride = null;
    super.dispose();
  }
}
