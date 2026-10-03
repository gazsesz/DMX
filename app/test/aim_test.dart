import 'package:dmx_controller/core/positions/aim.dart';
import 'package:dmx_controller/core/positions/group_positions.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_mounting.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/group_position.dart';
import 'package:dmx_controller/models/pan_tilt.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/stage_plan.dart';
import 'package:flutter_test/flutter_test.dart';

const _profile = FixtureProfile(
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
  ],
);

PatchedFixture _head(String id, double x, double y, {FixtureMounting mounting = const FixtureMounting()}) =>
    PatchedFixture(
      id: id,
      label: id,
      profile: _profile,
      universeId: 'u',
      startChannel: 0,
      layoutX: x,
      layoutY: y,
      mounting: mounting,
    );

AimRig _rig({double x = 4, double y = 0, FixtureMounting mounting = const FixtureMounting(heightM: 3)}) =>
    AimRig(x: x, y: y, mounting: mounting, panRangeDeg: 540, tiltRangeDeg: 270);

(double, double) _degrees(PanTilt p) => panTiltToDegrees(p, panRangeDeg: 540, tiltRangeDeg: 270);

void main() {
  group('PanTilt', () {
    test('splits into coarse and fine bytes and back', () {
      final p = PanTilt.fromChannels(pan: 0x12, panFine: 0x34, tilt: 0xAB, tiltFine: 0xCD);
      expect(p.pan, 0x1234);
      expect(p.tilt, 0xABCD);
      expect([p.panCoarse, p.panFine, p.tiltCoarse, p.tiltFine], [0x12, 0x34, 0xAB, 0xCD]);
    });

    test('centre is the middle of both channels', () {
      expect(PanTilt.center.panCoarse, 128);
      expect(PanTilt.center.tiltCoarse, 128);
    });
  });

  group('aimAt', () {
    test('a spot right under a hung head is tilt centre', () {
      final result = aimAt(_rig(), tx: 4, ty: 0, previous: PanTilt.center);
      final (pan, tilt) = _degrees(result.position);
      expect(result.reachable, isTrue);
      expect(tilt, closeTo(0, 0.05));
      expect(pan, closeTo(0, 0.05));
    });

    test('3 m down and 3 m towards the audience is 45° of tilt, no pan', () {
      final result = aimAt(_rig(), tx: 4, ty: 3);
      final (pan, tilt) = _degrees(result.position);
      expect(pan, closeTo(0, 0.05));
      expect(tilt.abs(), closeTo(45, 0.05));
    });

    test('a spot off to the side pans a quarter turn', () {
      final result = aimAt(_rig(), tx: 7, ty: 0);
      final (pan, tilt) = _degrees(result.position);
      expect(tilt.abs(), closeTo(45, 0.05));
      expect(pan.abs() % 180, closeTo(90, 0.05));
    });

    test('picks the way round closest to where the head already is', () {
      final previous = degreesToPanTilt(200, 30, panRangeDeg: 540, tiltRangeDeg: 270);
      final result = aimAt(_rig(), tx: 4, ty: 3, previous: previous);
      final (pan, _) = _degrees(result.position);
      // 0° and ±360° both point at the spot; 180° with tilt flipped does too.
      expect((pan - 200).abs(), lessThanOrEqualTo(20.0 + 0.05));
    });

    test('calibration offsets are added to the aimed position', () {
      final result = aimAt(
        _rig(mounting: const FixtureMounting(heightM: 3, panOffsetDeg: 4, tiltOffsetDeg: -2)),
        tx: 4,
        ty: 3,
        previous: PanTilt.center,
      );
      final (pan, tilt) = _degrees(result.position);
      expect(pan, closeTo(4, 0.05));
      expect(tilt, closeTo(45 - 2, 0.05));
    });

    test('a spot the head cannot reach is flagged and clamped', () {
      final narrow = AimRig(x: 4, y: 0, mounting: const FixtureMounting(heightM: 3), panRangeDeg: 540, tiltRangeDeg: 60);
      final result = aimAt(narrow, tx: 4, ty: 20);
      expect(result.reachable, isFalse);
      final (_, tilt) = panTiltToDegrees(result.position, panRangeDeg: 540, tiltRangeDeg: 60);
      expect(tilt.abs(), closeTo(30, 0.05));
    });
  });

  group('beamLandsAt', () {
    for (final mounting in [
      const FixtureMounting(heightM: 3),
      const FixtureMounting(heightM: 3, facingDeg: 90),
      const FixtureMounting(heightM: 3, invertPan: true, invertTilt: true),
      const FixtureMounting(heightM: 3, panOffsetDeg: 7, tiltOffsetDeg: -3),
      const FixtureMounting(mount: MountKind.standing, heightM: 0.4),
    ]) {
      test('is the inverse of aimAt (${mounting.toJson()})', () {
        final rig = _rig(mounting: mounting);
        final planeZ = mounting.mount == MountKind.standing ? 4.0 : 0.0;
        for (final (tx, ty) in [(4.0, 3.0), (1.5, 2.0), (6.0, 5.5), (2.0, 0.5)]) {
          final aimed = aimAt(rig, tx: tx, ty: ty, tz: planeZ);
          final landed = beamLandsAt(rig, aimed.position, planeZ: planeZ)!;
          expect(landed.$1, closeTo(tx, 0.02), reason: 'x for ($tx, $ty)');
          expect(landed.$2, closeTo(ty, 0.02), reason: 'y for ($tx, $ty)');
        }
      });
    }

    test('a beam pointing level never lands', () {
      final rig = _rig();
      final level = degreesToPanTilt(0, 90, panRangeDeg: 540, tiltRangeDeg: 270);
      expect(beamLandsAt(rig, level), isNull);
    });
  });

  group('resolveGroupPositions', () {
    const stage = StagePlan(widthM: 8, depthM: 6);
    final heads = [_head('c', 0.6, 0), _head('a', 0.2, 0), _head('d', 0.8, 0), _head('b', 0.4, 0)];

    test('a plain group puts every head on the shared position', () {
      final resolved = resolveGroupPositions(
        position: const GroupPosition(),
        base: const PanTilt(1000, 2000),
        fixtures: heads,
        stage: stage,
      );
      expect(resolved.values.map((r) => r.position).toSet(), {const PanTilt(1000, 2000)});
    });

    test('the fan spreads heads stage left to right around the base', () {
      final resolved = resolveGroupPositions(
        position: const GroupPosition(fanPanDeg: 10),
        base: PanTilt.center,
        fixtures: heads,
        stage: stage,
      );
      double pan(String id) => _degrees(resolved[id]!.position).$1;
      expect(pan('a'), closeTo(-15, 0.05));
      expect(pan('b'), closeTo(-5, 0.05));
      expect(pan('c'), closeTo(5, 0.05));
      expect(pan('d'), closeTo(15, 0.05));
    });

    test('a head set on its own ignores the fan', () {
      final resolved = resolveGroupPositions(
        position: const GroupPosition(fanPanDeg: 10, manual: {'a': PanTilt(5, 6)}),
        base: PanTilt.center,
        fixtures: heads,
        stage: stage,
      );
      expect(resolved['a']!.position, const PanTilt(5, 6));
    });

    test('mirror flips the pan of heads on the right half', () {
      final resolved = resolveGroupPositions(
        position: const GroupPosition(mirror: true),
        base: const PanTilt(40000, 30000),
        fixtures: heads,
        stage: stage,
      );
      expect(resolved['a']!.position.pan, 40000);
      expect(resolved['d']!.position.pan, PanTilt.max - 40000);
    });

    test('stage mode aims each head at its formation spot', () {
      final position = const GroupPosition(
        mode: PositionMode.stage,
        handle: StagePoint(0.5, 0.5),
        formation: StageFormation.line,
        spreadM: 2,
      );
      final resolved = resolveGroupPositions(position: position, base: PanTilt.center, fixtures: heads, stage: stage);
      final ordered = spreadOrder(heads);
      final xs = [for (final h in ordered) resolved[h.id]!.target!.x * stage.widthM];
      expect(xs, [for (final x in [1.0, 3.0, 5.0, 7.0]) closeTo(x, 1e-9)]);
      for (final head in heads) {
        final landed = beamLandsAt(aimRigFor(head, stage), resolved[head.id]!.position)!;
        expect(landed.$1, closeTo(resolved[head.id]!.target!.x * stage.widthM, 0.02));
        expect(landed.$2, closeTo(3, 0.02));
      }
    });

    test('switching to the stage view keeps every beam where it was', () {
      const start = GroupPosition(fanPanDeg: 8, fanTiltDeg: 3);
      final base = degreesToPanTilt(0, 35, panRangeDeg: 540, tiltRangeDeg: 270);
      final before = resolveGroupPositions(position: start, base: base, fixtures: heads, stage: stage);
      final staged = enterStageMode(start, before, heads, stage);
      final after = resolveGroupPositions(position: staged, base: base, fixtures: heads, stage: stage, previous: {
        for (final e in before.entries) e.key: e.value.position,
      });
      for (final head in heads) {
        final (p0, t0) = _degrees(before[head.id]!.position);
        final (p1, t1) = _degrees(after[head.id]!.position);
        expect(p1, closeTo(p0, 0.1), reason: head.id);
        expect(t1, closeTo(t0, 0.1), reason: head.id);
      }
    });

    test('moving the stage handle drags per-head spots along', () {
      const position = GroupPosition(
        mode: PositionMode.stage,
        handle: StagePoint(0.5, 0.5),
        aimOverrides: {'a': StagePoint(0.2, 0.4)},
      );
      final moved = moveHandle(position, const StagePoint(0.6, 0.6));
      expect(moved.aimOverrides['a']!.x, closeTo(0.3, 1e-9));
      expect(moved.aimOverrides['a']!.y, closeTo(0.5, 1e-9));
    });
  });

  group('GroupPosition json', () {
    test('round-trips a stage-mode group', () {
      const position = GroupPosition(
        mode: PositionMode.stage,
        fanPanDeg: 4,
        manual: {'a': PanTilt(1, 2)},
        handle: StagePoint(0.3, 0.7),
        formation: StageFormation.circle,
        spreadM: 2.5,
        aimHeightM: 1.7,
        aimOverrides: {'b': StagePoint(0.1, 0.2)},
      );
      final back = GroupPosition.fromJson(position.toJson());
      expect(back.mode, PositionMode.stage);
      expect(back.fanPanDeg, 4);
      expect(back.manual, {'a': const PanTilt(1, 2)});
      expect(back.handle, const StagePoint(0.3, 0.7));
      expect(back.formation, StageFormation.circle);
      expect(back.spreadM, 2.5);
      expect(back.aimHeightM, 1.7);
      expect(back.aimOverrides, {'b': const StagePoint(0.1, 0.2)});
    });
  });
}
