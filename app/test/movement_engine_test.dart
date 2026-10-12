import 'package:dmx_controller/core/movement/movement_engine.dart';
import 'package:dmx_controller/core/positions/aim.dart';
import 'package:dmx_controller/core/positions/group_positions.dart';
import 'package:dmx_controller/models/group_position.dart';
import 'package:dmx_controller/models/bank.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_group.dart';
import 'package:dmx_controller/models/fixture_mounting.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/movement_fx.dart';
import 'package:dmx_controller/models/pan_tilt.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/stage_plan.dart';
import 'package:flutter_test/flutter_test.dart';

const _mover = FixtureProfile(
  id: 'mover',
  name: 'Mover',
  category: FixtureCategory.movingHead,
  panRangeDeg: 540,
  tiltRangeDeg: 270,
  channels: [
    FixtureChannel(offset: 0, function: ChannelFunction.pan),
    FixtureChannel(offset: 1, function: ChannelFunction.panFine),
    FixtureChannel(offset: 2, function: ChannelFunction.tilt),
    FixtureChannel(offset: 3, function: ChannelFunction.tiltFine),
    FixtureChannel(offset: 4, function: ChannelFunction.dimmer),
  ],
);

const _par = FixtureProfile(
  id: 'par',
  name: 'Par',
  category: FixtureCategory.generic,
  channels: [FixtureChannel(offset: 0, function: ChannelFunction.dimmer)],
);

PatchedFixture _fixture(String id, FixtureProfile profile, {double x = 0.5, double y = 0.1, int start = 0}) =>
    PatchedFixture(id: id, label: id, profile: profile, universeId: 'u', startChannel: start, layoutX: x, layoutY: y);

void main() {
  group('shapes', () {
    test('every shape stays inside -1..1 and closes after one lap', () {
      for (final shape in MovementShape.values) {
        for (var i = 0; i <= 200; i++) {
          final (x, y) = shapeAt(shape, i / 200);
          expect(x.abs(), lessThanOrEqualTo(1.0001), reason: '$shape x at $i');
          expect(y.abs(), lessThanOrEqualTo(1.0001), reason: '$shape y at $i');
        }
        final (x0, y0) = shapeAt(shape, 0);
        final (x1, y1) = shapeAt(shape, 1);
        expect(x1, closeTo(x0, 1e-9), reason: '$shape closes in x');
        expect(y1, closeTo(y0, 1e-9), reason: '$shape closes in y');
      }
    });

    test('circle is round and the sweep is constant speed', () {
      for (var i = 0; i < 20; i++) {
        final (x, y) = shapeAt(MovementShape.circle, i / 20);
        expect(x * x + y * y, closeTo(1, 1e-9));
      }
      final a = shapeAt(MovementShape.sweep, 0.05).$1;
      final b = shapeAt(MovementShape.sweep, 0.10).$1;
      final c = shapeAt(MovementShape.sweep, 0.15).$1;
      expect(b - a, closeTo(c - b, 1e-9));
    });

    test('light rider eases into its ends, sweep does not', () {
      double slopeAtEnd(MovementShape s) => (shapeAt(s, 0.25).$1 - shapeAt(s, 0.24).$1).abs();
      expect(slopeAtEnd(MovementShape.lightRider), lessThan(slopeAtEnd(MovementShape.sweep) / 4));
    });

    test('square visits its corners', () {
      expect(shapeAt(MovementShape.square, 0.25), (1.0, -1.0));
      expect(shapeAt(MovementShape.square, 0.5), (1.0, 1.0));
    });
  });

  group('clock', () {
    test('free run: one lap takes the period', () {
      const fx = MovementFx(periodSec: 4);
      final clock = MovementClock();
      for (var i = 0; i < 100; i++) {
        clock.tick(const Duration(milliseconds: 20), fx);
      }
      expect(clock.phase, closeTo(0.5, 1e-9));
    });

    test('beat-locked: lap is beats times the beat interval', () {
      const fx = MovementFx(beatLocked: true, beats: 4);
      final clock = MovementClock(beatInterval: const Duration(milliseconds: 500));
      expect(clock.lap(fx), const Duration(seconds: 2));
      clock.onBeat(fx, interval: const Duration(milliseconds: 400));
      expect(clock.lap(fx), const Duration(milliseconds: 1600));
    });

    test('a beat nudges the phase towards the beat grid without jumping', () {
      const fx = MovementFx(beatLocked: true, beats: 4);
      final clock = MovementClock(phase: 0.30); // grid points are 0, .25, .5 ...
      clock.onBeat(fx);
      expect(clock.phase, lessThan(0.30));
      expect(clock.phase, greaterThan(0.25));
    });

    test('a beat does nothing to a free-running effect', () {
      const fx = MovementFx();
      final clock = MovementClock(phase: 0.3);
      clock.onBeat(fx);
      expect(clock.phase, 0.3);
    });

    test('ignores a beat gap that means the music stopped', () {
      const fx = MovementFx(beatLocked: true);
      final clock = MovementClock();
      clock.onBeat(fx, interval: const Duration(seconds: 9));
      expect(clock.beatInterval, const Duration(milliseconds: 500));
    });
  });

  group('heads', () {
    final fixtures = [
      _fixture('a', _mover, x: 0.8),
      _fixture('par', _par, x: 0.5),
      _fixture('b', _mover, x: 0.2, start: 10),
    ];

    test('picks the movers, stage left to right', () {
      final heads = movementHeads(const MovementFx(), fixtures, const []);
      expect(heads.map((h) => h.fixture.id), ['b', 'a']);
      expect(heads.first.panFineOffset, 1);
      expect(heads.first.tiltOffset, 2);
    });

    test('narrows to groups and fixtures', () {
      const group = FixtureGroup(id: 'g', name: 'G', iconKey: 'all', fixtureIds: ['a']);
      expect(movementHeads(const MovementFx(groupIds: {'g'}), fixtures, [group]).map((h) => h.fixture.id), ['a']);
      expect(movementHeads(const MovementFx(fixtureIds: {'b'}), fixtures, const []).map((h) => h.fixture.id), ['b']);
    });
  });

  group('frame', () {
    final fixtures = [_fixture('a', _mover, x: 0.2), _fixture('b', _mover, x: 0.8)];
    final heads = movementHeads(const MovementFx(), fixtures, const []);
    const stage = StagePlan();

    test('pan/tilt circle sweeps the configured angle round the centre', () {
      const fx = MovementFx(sizePanDeg: 45, sizeTiltDeg: 45);
      final start = movementFrame(fx, heads, 0, stage)['a']!;
      final quarter = movementFrame(fx, heads, 0.25, stage)['a']!;
      final (pan0, tilt0) = panTiltToDegrees(start, panRangeDeg: 540, tiltRangeDeg: 270);
      final (pan1, tilt1) = panTiltToDegrees(quarter, panRangeDeg: 540, tiltRangeDeg: 270);
      expect(pan0, closeTo(45, 0.1));
      expect(tilt0, closeTo(0, 0.1));
      expect(pan1, closeTo(0, 0.1));
      expect(tilt1, closeTo(45, 0.1));
    });

    test('phase spread offsets the heads round the lap', () {
      const together = MovementFx(shape: MovementShape.panSweep);
      const spread = MovementFx(shape: MovementShape.panSweep, phaseSpread: 1);
      final same = movementFrame(together, heads, 0.1, stage);
      expect(same['a'], same['b']);
      final waved = movementFrame(spread, heads, 0.1, stage);
      expect(waved['a'], isNot(waved['b']));
    });

    test('reverse runs the path backwards', () {
      const forward = MovementFx(shape: MovementShape.panSweep);
      final reverse = forward.copyWith(reverse: true);
      final f = movementFrame(forward, heads, 0.1, stage)['a']!;
      final r = movementFrame(reverse, heads, 0.1, stage)['a']!;
      expect(r.pan - PanTilt.center.pan, closeTo(-(f.pan - PanTilt.center.pan), 2));
    });

    test('mirror swings the right-hand head the other way in pan', () {
      const fx = MovementFx(shape: MovementShape.panSweep, mirror: true);
      final frame = movementFrame(fx, heads, 0.1, stage);
      expect(frame['a']!.pan - PanTilt.center.pan, closeTo(-(frame['b']!.pan - PanTilt.center.pan), 2));
    });

    test('rotation turns a pan sweep into a tilt move', () {
      const fx = MovementFx(shape: MovementShape.panSweep, rotationDeg: 90);
      final frame = movementFrame(fx, heads, 0.25, stage)['a']!;
      expect(frame.pan, closeTo(PanTilt.center.pan, 2));
      expect(frame.tilt, isNot(closeTo(PanTilt.center.tilt, 100)));
    });

    test('a head with a narrower tilt range still gets the same angle', () {
      final narrow = _fixture('n', _mover.copyWith(tiltRangeDeg: 180));
      final h = movementHeads(const MovementFx(), [narrow], const []);
      const fx = MovementFx(shape: MovementShape.tiltSweep, sizeTiltDeg: 30);
      final frame = movementFrame(fx, h, 0.25, stage)['n']!;
      final (_, tilt) = panTiltToDegrees(frame, panRangeDeg: 540, tiltRangeDeg: 180);
      expect(tilt, closeTo(30, 0.1));
    });

    test('stage space draws the path on the floor: beams land on a circle', () {
      final hung = _fixture('h', _mover, x: 0.5, y: 0.1);
      final rig = aimRigFor(hung, stage);
      final h = movementHeads(const MovementFx(), [hung.copyWith(mounting: const FixtureMounting(heightM: 4))], const []);
      const fx = MovementFx(space: MovementSpace.stage, sizeXM: 1.5, sizeYM: 1.5, stageCenter: StagePoint(0.5, 0.6));
      Map<String, PanTilt> previous = {};
      for (var i = 0; i < 8; i++) {
        final frame = movementFrame(fx, h, i / 8, stage, previous: previous);
        previous = frame;
        final landed = beamLandsAt(
          AimRig(
            x: rig.x,
            y: rig.y,
            mounting: const FixtureMounting(heightM: 4),
            panRangeDeg: 540,
            tiltRangeDeg: 270,
          ),
          frame['h']!,
        )!;
        final dx = landed.$1 - 0.5 * stage.widthM;
        final dy = landed.$2 - 0.6 * stage.depthM;
        expect(dx * dx + dy * dy, closeTo(1.5 * 1.5, 0.05), reason: 'point $i');
      }
    });
  });

  test('lerpPanTilt', () {
    expect(lerpPanTilt(const PanTilt(0, 100), const PanTilt(100, 0), 0.5), const PanTilt(50, 50));
    expect(lerpPanTilt(const PanTilt(0, 0), const PanTilt(10, 10), 2), const PanTilt(10, 10));
  });

  group('persistence', () {
    test('a Movement FX bank round-trips and plain banks stay plain', () {
      const fx = MovementFx(
        shape: MovementShape.swim,
        space: MovementSpace.stage,
        beatLocked: true,
        beats: 8,
        phaseSpread: 0.5,
        groupIds: {'g1'},
        center: PanTilt(1000, 2000),
      );
      final bank = Bank(id: 'b', name: 'Swim', sceneSlots: const [], fx: fx);
      final loaded = Bank.fromJson(bank.toJson());
      expect(loaded.isMovementFx, isTrue);
      expect(loaded.fx, fx);
      expect(loaded.fx!.center, const PanTilt(1000, 2000));

      final plain = Bank.fromJson(const Bank(id: 'p', name: 'P', sceneSlots: [null]).toJson());
      expect(plain.isMovementFx, isFalse);
      expect(plain.toJson().containsKey('fx'), isFalse);
    });

    test('out-of-range values are clamped when loading', () {
      final fx = MovementFx.fromJson({'shape': 'nope', 'periodSec': 0, 'sizePanDeg': 9999})!;
      expect(fx.shape, MovementShape.circle);
      expect(fx.periodSec, MovementFx.periodRange.min);
      expect(fx.sizePanDeg, 270);
    });
  });

  group('random, hold and fan', () {
    test('random wanders but repeats the same path every lap', () {
      final a = shapeAt(MovementShape.random, 0.37);
      final again = shapeAt(MovementShape.random, 1.37);
      expect(again.$1, closeTo(a.$1, 1e-9));
      expect(again.$2, closeTo(a.$2, 1e-9));
      final xs = {for (var i = 0; i < 40; i++) shapeAt(MovementShape.random, i / 40).$1.toStringAsFixed(2)};
      expect(xs.length, greaterThan(10));
    });

    test('different seeds visit different spots', () {
      expect(shapeAt(MovementShape.random, 0.3, seed: 1), isNot(shapeAt(MovementShape.random, 0.3, seed: 2)));
    });

    test('random jumps sit still for most of each step', () {
      // Spots change every 1/8 lap; the last 80% of a step is a hold.
      final held = shapeAt(MovementShape.randomJump, 0.125 * 3 + 0.125 * 0.5);
      final later = shapeAt(MovementShape.randomJump, 0.125 * 3 + 0.125 * 0.9);
      expect(later, held);
    });

    test('hold stays at the centre', () {
      expect(shapeAt(MovementShape.hold, 0.4), (0.0, 0.0));
    });

    test('fan spreads the heads round the middle without touching the path', () {
      const fx = MovementFx(shape: MovementShape.hold, fanPanDeg: 10);
      expect(movementOffset(fx, 0, 3, 0).$1, closeTo(-10, 1e-9));
      expect(movementOffset(fx, 1, 3, 0).$1, closeTo(0, 1e-9));
      expect(movementOffset(fx, 2, 3, 0).$1, closeTo(10, 1e-9));
      const stage = MovementFx(shape: MovementShape.hold, space: MovementSpace.stage, fanXM: 1.5);
      expect(movementOffset(stage, 0, 2, 0).$1, closeTo(-0.75, 1e-9));
    });

    test('a fan on a hold puts real heads that many degrees apart', () {
      final fixtures = [_fixture('a', _mover, x: 0.2), _fixture('b', _mover, x: 0.8)];
      final heads = movementHeads(const MovementFx(), fixtures, const []);
      const fx = MovementFx(shape: MovementShape.hold, fanPanDeg: 20);
      final frame = movementFrame(fx, heads, 0, const StagePlan());
      final (panA, _) = panTiltToDegrees(frame['a']!, panRangeDeg: 540, tiltRangeDeg: 270);
      final (panB, _) = panTiltToDegrees(frame['b']!, panRangeDeg: 540, tiltRangeDeg: 270);
      expect(panB - panA, closeTo(20, 0.1));
    });

    test('the new settings survive JSON', () {
      const fx = MovementFx(shape: MovementShape.randomJump, fanPanDeg: 12, fanXM: 0.5);
      final back = MovementFx.fromJson(fx.toJson())!;
      expect(back, fx);
      expect(back.fanPanDeg, 12);
    });
  });
}
