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
/// size, rotation and fan are applied. [seed] picks the spots the random
/// shapes wander between; the other shapes ignore it.
(double, double) shapeAt(MovementShape shape, double phase, {int seed = 0}) {
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
    case MovementShape.random:
      return _randomWander(phase, seed, jump: false);
    case MovementShape.randomJump:
      return _randomWander(phase, seed, jump: true);
    case MovementShape.hold:
      return (0, 0);
  }
}

/// Spots a lap visits in the random shapes. The last one is the first again,
/// so the lap closes.
const _randomSpots = 8;

/// A fixed "random" spot in -0.9..0.9 on each axis for spot [index] of the
/// head with [seed] — the same every lap, so the path is repeatable.
(double, double) _spot(int index, int seed) {
  int mix(int v) {
    var h = (v * 0x45D9F3B) & 0x7FFFFFFF;
    h = ((h >> 16) ^ h) * 0x45D9F3B & 0x7FFFFFFF;
    return ((h >> 16) ^ h) & 0xFFFF;
  }

  final i = index % _randomSpots;
  final x = mix(i * 2 + 1 + seed * 977) / 0xFFFF * 2 - 1;
  final y = mix(i * 2 + 2 + seed * 977) / 0xFFFF * 2 - 1;
  return (x * 0.9, y * 0.9);
}

(double, double) _randomWander(double phase, int seed, {required bool jump}) {
  final p = (phase - phase.floorToDouble()) * _randomSpots;
  final index = p.floor();
  var f = p - index;
  final a = _spot(index, seed);
  final b = _spot(index + 1, seed);
  // Smooth: ease between spots the whole way. Jump: make the move in the
  // first fifth of the step and sit still for the rest.
  f = jump ? ((f / 0.2).clamp(0.0, 1.0)) : f;
  final e = f * f * (3 - 2 * f);
  return (a.$1 + (b.$1 - a.$1) * e, a.$2 + (b.$2 - a.$2) * e);
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
  void onBeat(MovementFx fx, {Duration? interval, bool nudge = true}) {
    if (interval != null && interval >= const Duration(milliseconds: 200) && interval <= const Duration(seconds: 2)) {
      beatInterval = interval;
    }
    if (!nudge || !fx.beatLocked || fx.beats <= 0) return;
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

/// Where head [index] of [count] is [phase] of the way round, as an offset
/// from the middle of the path: degrees of pan/tilt in pan/tilt space,
/// metres across and along the stage in stage space. Size, rotation, wave,
/// mirror, direction and fan are all in it.
///
/// This is the one place those are worked out, so what the editor's preview
/// draws is what the heads do. [rightOfCentre] is for the mirror option.
(double, double) movementOffset(
  MovementFx fx,
  int index,
  int count,
  double phase, {
  bool rightOfCentre = false,
}) {
  var headPhase = phase + (count > 1 ? index / count * fx.phaseSpread : 0);
  if (fx.reverse) headPhase = -headPhase;
  // Heads on a wave each get their own spots when the shape is random.
  final (rawX, rawY) = shapeAt(fx.shape, headPhase, seed: fx.phaseSpread > 0 ? index : 0);
  final x = fx.mirror && rightOfCentre ? -rawX : rawX;
  final stage = fx.space == MovementSpace.stage;
  final dx = x * (stage ? fx.sizeXM : fx.sizePanDeg);
  final dy = rawY * (stage ? fx.sizeYM : fx.sizeTiltDeg);
  final rotation = fx.rotationDeg * math.pi / 180;
  final fan = (index - (count - 1) / 2) * (stage ? fx.fanXM : fx.fanPanDeg);
  return (
    dx * math.cos(rotation) - dy * math.sin(rotation) + fan,
    dx * math.sin(rotation) + dy * math.cos(rotation),
  );
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
  for (var i = 0; i < n; i++) {
    final fixture = heads[i].fixture;
    final (dx, dy) = movementOffset(fx, i, n, phase, rightOfCentre: fixture.layoutX > 0.5);

    if (fx.space == MovementSpace.stage) {
      final aimed = aimAt(
        aimRigFor(fixture, stage),
        tx: fx.stageCenter.x * stage.widthM + dx,
        ty: fx.stageCenter.y * stage.depthM + dy,
        tz: fx.aimHeightM,
        previous: previous[fixture.id] ?? fx.center,
      );
      result[fixture.id] = aimed.position;
    } else {
      final panRange = fixture.profile.panRangeDeg;
      final tiltRange = fixture.profile.tiltRangeDeg;
      final (centerPan, centerTilt) = panTiltToDegrees(fx.center, panRangeDeg: panRange, tiltRangeDeg: tiltRange);
      result[fixture.id] = degreesToPanTilt(
        centerPan + dx,
        centerTilt + dy,
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
