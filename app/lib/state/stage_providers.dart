import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/pan_tilt.dart';
import '../models/position_preset.dart';
import '../models/stage_plan.dart';

const _uuid = Uuid();

/// The stage plan's real size and named aim targets — project-scoped, like
/// the layout positions it gives a scale to.
final stagePlanProvider = StateNotifierProvider<StagePlanNotifier, StagePlan>((ref) => StagePlanNotifier());

class StagePlanNotifier extends StateNotifier<StagePlan> {
  StagePlanNotifier() : super(const StagePlan());

  void setSize({required double widthM, required double depthM}) {
    state = state.copyWith(widthM: widthM.clamp(1.0, 200.0), depthM: depthM.clamp(1.0, 200.0));
  }

  AimTarget addTarget({required String name, required double x, required double y, required double heightM}) {
    final target = AimTarget(
      id: _uuid.v4(),
      name: name,
      x: x.clamp(0.0, 1.0),
      y: y.clamp(0.0, 1.0),
      heightM: heightM.clamp(0.0, 50.0),
    );
    state = state.copyWith(targets: [...state.targets, target]);
    return target;
  }

  void updateTarget(String id, AimTarget Function(AimTarget current) updater) {
    state = state.copyWith(targets: [for (final t in state.targets) if (t.id == id) updater(t) else t]);
  }

  void removeTarget(String id) {
    state = state.copyWith(targets: state.targets.where((t) => t.id != id).toList());
  }

  void load(StagePlan plan) => state = plan;
}

/// Saved position presets for the current rig (see [PositionPreset]).
final positionPresetsProvider = StateNotifierProvider<PositionPresetsNotifier, List<PositionPreset>>(
  (ref) => PositionPresetsNotifier(),
);

class PositionPresetsNotifier extends StateNotifier<List<PositionPreset>> {
  PositionPresetsNotifier() : super(const []);

  PositionPreset create({required String name, required Map<String, PanTilt> perFixture}) {
    final preset = PositionPreset(id: _uuid.v4(), name: name, perFixture: Map.unmodifiable(perFixture));
    state = [...state, preset];
    return preset;
  }

  /// Folds [perFixture] into the preset — fixtures it already had but that
  /// aren't in [perFixture] keep their stored position, so re-saving a preset
  /// from a scene that only holds half the rig doesn't forget the other half.
  void merge(String id, Map<String, PanTilt> perFixture) {
    state = [
      for (final p in state)
        if (p.id == id) p.copyWith(perFixture: Map.unmodifiable({...p.perFixture, ...perFixture})) else p,
    ];
  }

  void rename(String id, String name) {
    state = [for (final p in state) if (p.id == id) p.copyWith(name: name) else p];
  }

  void remove(String id) {
    state = state.where((p) => p.id != id).toList();
  }

  void loadAll(List<PositionPreset> presets) => state = presets;
}
