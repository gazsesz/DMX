import 'dart:math' as math;

import '../../models/channel_function.dart';
import '../../models/fixture_group.dart';
import '../../models/movement_fx.dart';
import '../../models/pan_tilt.dart';
import '../../models/patched_fixture.dart';
import '../../models/stage_plan.dart';
import '../positions/aim.dart';
import '../positions/group_positions.dart';

/// The raw path at [phase] (0..1 of one lap), each axis in -1..1 — before
/// size, rotation and fan are applied.
(double, double) shapeAt(MovementShape shape, double phase) {
  final t = 2 * math.pi * phase;
  switch (shape) {
    case MovementShape.circle:
      return (math.cos(t), math.sin(t));
    case MovementShape.panSweep:
      return (math.sin(t), 0);
    case MovementShape.tiltSweep:
      return (0, math.sin(t));
    case MovementShape.sweep:
      return (_triangle(phase), 0);
    case MovementShape.lightRider:
      // Eased turnarounds: a triangle with each end rounded off.
      final x = _triangle(phase);
      return (x * (1.5 - 0.5 * x * x), 0);
    case MovementShape.swim:
      return (math.sin(t), math.sin(2 * t) * 0.6);
    case MovementShape.float:
      return (math.sin(t) * 0.6 + math.sin(3 * t) * 0.25, math.cos(2 * t) * 0.45);
    case MovementShape.square:
      return _polygon(const [(-1, -1), (1, -1), (1, 1), (-1, 1)], phase);
    case MovementShape.diamond:
      return _polygon(const [(0, -1), (1, 0), (0, 1), (-1, 0)], phase);
  }
}

/// -1 → 1 → -1 at a constant rate, starting at 0 going up.
double _triangle(double phase) {
  final p = phase - phase.floorToDouble();
  return p < 0.25 ? 4 * p : (p < 0.75 ? 2 - 4 * p : 4 * p - 4);
}

(double, double) _polygon(List<(double, double)> corners, double phase) {
  final p = (phase - phase.floorToDouble()) * corners.length;
  final index = p.floor() % corners.length;
  final f = p - p.floor();
  final a = corners[index];
  final b = corners[(index + 1) % corners.length];
  return (a.$1 + (b.$1 - a.$1) * f, a.$2 + (b.$2 - a.$2) * f);
}

/// Where one lap has got to, advanced by elapsed time and (when locked to
/// the beat) nudged onto the beat grid so it neither drifts nor jumps.
class MovementClock {
  double phase;
  Duration beatInterval;

  MovementClock({this.phase = 0, this.beatInterval = const Duration(milliseconds: 500)});

  /// Length of one lap right now.
  Duration lap(MovementFx fx) => fx.beatLocked
      ? Duration(microseconds: (beatInterval.inMicroseconds * fx.beats).round())
      : Duration(microseconds: (fx.periodSec * 1000000).round());

  void tick(Duration elapsed, MovementFx fx) {
    final lapUs = lap(fx).inMicroseconds;
    if (lapUs <= 0) return;
    phase = (phase + elapsed.inMicroseconds / lapUs) % 1.0;
  }

  /// A beat arrived. [interval] is the gap since the one before, when known.
  /// For a beat-locked effect the lap is pulled a third of the way towards
  /// the nearest beat boundary, so a late or early beat is absorbed over a
  /// few beats instead of making the heads jump.
  void onBeat(MovementFx fx, {Duration? interval}) {
    if (interval != null && interval >= const Duration(milliseconds: 200) && interval <= const Duration(seconds: 2)) {
      beatInterval = interval;
    }
    if (!fx.beatLocked || fx.beats <= 0) return;
    final unit = 1 / fx.beats;
    final target = (phase / unit).round() * unit;
    phase = (phase + (target - phase) * 0.35) % 1.0;
    if (phase < 0) phase += 1;
  }
}

/// One mover the effect drives, with where its pan/tilt channels sit.
class MovementHead {
  final PatchedFixture fixture;
  final int panOffset;
  final int? panFineOffset;
  final int tiltOffset;
  final int? tiltFineOffset;

  const MovementHead({
    required this.fixture,
    required this.panOffset,
    this.panFineOffset,
    required this.tiltOffset,
    this.tiltFineOffset,
  });

  /// Every channel offset this head writes.
  Iterable<int> get offsets => [panOffset, ?panFineOffset, tiltOffset, ?tiltFineOffset];
}

/// The heads [fx] drives, in the order fan and phase spread count them off:
/// moving heads with pan and tilt, narrowed to the effect's groups/fixtures.
List<MovementHead> movementHeads(MovementFx fx, Iterable<PatchedFixture> fixtures, Iterable<FixtureGroup> groups) {
  final wanted = <String>{
    ...fx.fixtureIds,
    for (final group in groups)
      if (fx.groupIds.contains(group.id)) ...group.fixtureIds,
  };
  final restrict = fx.groupIds.isNotEmpty || fx.fixtureIds.isNotEmpty;
  final heads = <MovementHead>[];
  for (final fixture in spreadOrder(fixtures)) {
    if (restrict && !wanted.contains(fixture.id)) continue;
    int? offsetOf(ChannelFunction function) {
      for (final channel in fixture.profile.channels) {
        if (channel.function == function) return channel.offset;
      }
      return null;
    }

    final pan = offsetOf(ChannelFunction.pan);
    final tilt = offsetOf(ChannelFunction.tilt);
    if (pan == null || tilt == null) continue;
    heads.add(MovementHead(
      fixture: fixture,
      panOffset: pan,
      panFineOffset: offsetOf(ChannelFunction.panFine),
      tiltOffset: tilt,
      tiltFineOffset: offsetOf(ChannelFunction.tiltFine),
    ));
  }
  return heads;
}

/// Every head's pan/tilt at the lap position [phase].
///
/// [previous] is where each head is now (by fixture id), which stage-space
/// aiming uses to keep choosing the same way round.
Map<String, PanTilt> movementFrame(
  MovementFx fx,
  List<MovementHead> heads,
  double phase,
  StagePlan stage, {
  Map<String, PanTilt> previous = const {},
}) {
  final result = <String, PanTilt>{};
  final n = heads.length;
  final rotation = fx.rotationDeg * math.pi / 180;
  final cosR = math.cos(rotation);
  final sinR = math.sin(rotation);
  for (var i = 0; i < n; i++) {
    final fixture = heads[i].fixture;
    var headPhase = phase + (n > 1 ? i / n * fx.phaseSpread : 0);
    if (fx.reverse) headPhase = -headPhase;
    final (rawX, rawY) = shapeAt(fx.shape, headPhase);
    var x = rawX;
    final y = rawY;
    if (fx.mirror && fixture.layoutX > 0.5) x = -x;

    if (fx.space == MovementSpace.stage) {
      final dx = x * fx.sizeXM;
      final dy = y * fx.sizeYM;
      final aimed = aimAt(
        aimRigFor(fixture, stage),
        tx: fx.stageCenter.x * stage.widthM + dx * cosR - dy * sinR,
        ty: fx.stageCenter.y * stage.depthM + dx * sinR + dy * cosR,
        tz: fx.aimHeightM,
        previous: previous[fixture.id] ?? fx.center,
      );
      result[fixture.id] = aimed.position;
    } else {
      final dx = x * fx.sizePanDeg;
      final dy = y * fx.sizeTiltDeg;
      final panRange = fixture.profile.panRangeDeg;
      final tiltRange = fixture.profile.tiltRangeDeg;
      final (centerPan, centerTilt) = panTiltToDegrees(fx.center, panRangeDeg: panRange, tiltRangeDeg: tiltRange);
      result[fixture.id] = degreesToPanTilt(
        centerPan + dx * cosR - dy * sinR,
        centerTilt + dx * sinR + dy * cosR,
        panRangeDeg: panRange,
        tiltRangeDeg: tiltRange,
      );
    }
  }
  return result;
}

/// [from] eased [t] (0..1) of the way to [to].
PanTilt lerpPanTilt(PanTilt from, PanTilt to, double t) {
  if (t >= 1) return to;
  if (t <= 0) return from;
  return PanTilt(
    (from.pan + (to.pan - from.pan) * t).round(),
    (from.tilt + (to.tilt - from.tilt) * t).round(),
  ).clamped();
}
