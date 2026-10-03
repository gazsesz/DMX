import 'dart:math' as math;

import '../../models/group_position.dart';
import '../../models/pan_tilt.dart';
import '../../models/patched_fixture.dart';
import '../../models/stage_plan.dart';
import 'aim.dart';

/// Where one head of a group ends up.
class ResolvedPosition {
  final PanTilt position;

  /// False when stage mode asked for a spot this head can't turn to.
  final bool reachable;

  /// Stage mode: the spot on the plan this head is aimed at.
  final StagePoint? target;

  const ResolvedPosition(this.position, {this.reachable = true, this.target});
}

/// The order a group's heads count off in for the fan and the formations:
/// stage left to right, then upstage to down, then by name.
List<PatchedFixture> spreadOrder(Iterable<PatchedFixture> fixtures) {
  return fixtures.toList()..sort((a, b) {
    final byX = a.layoutX.compareTo(b.layoutX);
    if (byX != 0) return byX;
    final byY = a.layoutY.compareTo(b.layoutY);
    return byY != 0 ? byY : a.label.compareTo(b.label);
  });
}

AimRig aimRigFor(PatchedFixture fixture, StagePlan stage) => AimRig(
  x: fixture.layoutX * stage.widthM,
  y: fixture.layoutY * stage.depthM,
  mounting: fixture.mounting,
  panRangeDeg: fixture.profile.panRangeDeg,
  tiltRangeDeg: fixture.profile.tiltRangeDeg,
);

/// Where each head of a stage-mode group is aimed, before any per-head drag.
Map<String, StagePoint> formationTargets(GroupPosition position, List<PatchedFixture> ordered, StagePlan stage) {
  final n = ordered.length;
  final handle = position.handle;
  final result = <String, StagePoint>{};
  for (var i = 0; i < n; i++) {
    final StagePoint point;
    switch (position.formation) {
      case StageFormation.point:
        point = handle;
      case StageFormation.line:
        final offsetM = (i - (n - 1) / 2) * position.spreadM;
        point = StagePoint(handle.x + offsetM / stage.widthM, handle.y);
      case StageFormation.circle:
        final radiusM = n < 2 ? 0.0 : position.spreadM / 2;
        final angle = 2 * math.pi * i / n;
        point = StagePoint(
          handle.x + radiusM * math.sin(angle) / stage.widthM,
          handle.y - radiusM * math.cos(angle) / stage.depthM,
        );
    }
    result[ordered[i].id] = point.clamped();
  }
  return result;
}

/// Every head's position in a group, from the shared [base] pan/tilt and
/// the group's [position] settings.
///
/// [previous] is where each head was last time round, so stage-mode aiming
/// keeps choosing the same way round (see [aimAt]).
Map<String, ResolvedPosition> resolveGroupPositions({
  required GroupPosition position,
  required PanTilt base,
  required Iterable<PatchedFixture> fixtures,
  required StagePlan stage,
  Map<String, PanTilt> previous = const {},
}) {
  final ordered = spreadOrder(fixtures);
  final result = <String, ResolvedPosition>{};

  if (position.mode == PositionMode.stage) {
    final targets = formationTargets(position, ordered, stage);
    for (final fixture in ordered) {
      final target = position.aimOverrides[fixture.id] ?? targets[fixture.id]!;
      final aimed = aimAt(
        aimRigFor(fixture, stage),
        tx: target.x * stage.widthM,
        ty: target.y * stage.depthM,
        tz: position.aimHeightM,
        previous: previous[fixture.id] ?? base,
      );
      result[fixture.id] = ResolvedPosition(aimed.position, reachable: aimed.reachable, target: target);
    }
    return result;
  }

  final n = ordered.length;
  for (var i = 0; i < n; i++) {
    final fixture = ordered[i];
    final manual = position.manual[fixture.id];
    if (manual != null) {
      result[fixture.id] = ResolvedPosition(manual);
      continue;
    }
    final step = i - (n - 1) / 2;
    var pan = base.pan + position.fanPanDeg * step / fixture.profile.panRangeDeg * PanTilt.max;
    final tilt = base.tilt + position.fanTiltDeg * step / fixture.profile.tiltRangeDeg * PanTilt.max;
    if (position.mirror && fixture.layoutX > 0.5) pan = PanTilt.max - pan;
    result[fixture.id] = ResolvedPosition(PanTilt(pan.round(), tilt.round()).clamped());
  }
  return result;
}

/// Switching a group from the pad to the stage view: every head's beam is
/// pinned where it already lands and the handle sits in the middle of them,
/// so nothing moves until you drag something.
///
/// A head pointing level or up (no spot on the floor), or landing off the
/// plan, is left to the formation instead.
GroupPosition enterStageMode(
  GroupPosition position,
  Map<String, ResolvedPosition> current,
  Iterable<PatchedFixture> fixtures,
  StagePlan stage,
) {
  final landed = <String, StagePoint>{};
  for (final fixture in fixtures) {
    final now = current[fixture.id];
    if (now == null) continue;
    final spot = beamLandsAt(aimRigFor(fixture, stage), now.position, planeZ: position.aimHeightM);
    if (spot == null) continue;
    final point = StagePoint(spot.$1 / stage.widthM, spot.$2 / stage.depthM);
    if (point.x < 0 || point.x > 1 || point.y < 0 || point.y > 1) continue;
    landed[fixture.id] = point;
  }
  if (landed.isEmpty) return position.copyWith(mode: PositionMode.stage, aimOverrides: const {});
  final cx = landed.values.map((p) => p.x).reduce((a, b) => a + b) / landed.length;
  final cy = landed.values.map((p) => p.y).reduce((a, b) => a + b) / landed.length;
  return position.copyWith(mode: PositionMode.stage, handle: StagePoint(cx, cy), aimOverrides: landed);
}

/// Switching back to the pad: each head keeps the exact pan/tilt the stage
/// view gave it, as a per-head position the pad then moves as one.
GroupPosition enterPadMode(GroupPosition position, Map<String, ResolvedPosition> current) {
  return position.copyWith(
    mode: PositionMode.pad,
    manual: {for (final e in current.entries) e.key: e.value.position},
    aimOverrides: const {},
  );
}

/// Dragging the pad's shared handle by [delta]: heads set on their own move
/// along with it, so a recalled preset can be nudged as a whole.
GroupPosition shiftManual(GroupPosition position, PanTilt delta) {
  if (position.manual.isEmpty) return position;
  return position.copyWith(
    manual: {for (final e in position.manual.entries) e.key: (e.value + delta).clamped()},
  );
}

/// Dragging the stage handle: beams dragged to their own spot come along.
GroupPosition moveHandle(GroupPosition position, StagePoint to) {
  final target = to.clamped();
  final dx = target.x - position.handle.x;
  final dy = target.y - position.handle.y;
  return position.copyWith(
    handle: target,
    aimOverrides: {
      for (final e in position.aimOverrides.entries) e.key: StagePoint(e.value.x + dx, e.value.y + dy).clamped(),
    },
  );
}
