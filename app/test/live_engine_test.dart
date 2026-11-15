import 'package:dmx_controller/core/live/live_engine.dart';
import 'package:dmx_controller/models/channel_capability.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/live_grid.dart';
import 'package:dmx_controller/models/movement_fx.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/universe_config.dart';
import 'package:flutter_test/flutter_test.dart';

const _universe = UniverseConfig(id: 'u', name: 'U', universe: 0);

const _head = FixtureProfile(
  id: 'head',
  name: 'Head',
  category: FixtureCategory.movingHead,
  panRangeDeg: 540,
  tiltRangeDeg: 270,
  channels: [
    FixtureChannel(offset: 0, function: ChannelFunction.pan),
    FixtureChannel(offset: 1, function: ChannelFunction.tilt),
    FixtureChannel(offset: 2, function: ChannelFunction.dimmer),
    FixtureChannel(
      offset: 3,
      function: ChannelFunction.strobe,
      capabilities: [
        ChannelCapability(min: 0, max: 3, label: 'Closed', kind: CapabilityKind.off),
        ChannelCapability(min: 4, max: 7, label: 'Open'),
        ChannelCapability(min: 8, max: 215, label: 'Strobe slow to fast', kind: CapabilityKind.range),
      ],
    ),
    FixtureChannel(offset: 4, function: ChannelFunction.gobo),
  ],
);

const _par = FixtureProfile(
  id: 'par',
  name: 'Par',
  category: FixtureCategory.generic,
  channels: [
    FixtureChannel(offset: 0, function: ChannelFunction.red),
    FixtureChannel(offset: 1, function: ChannelFunction.green),
    FixtureChannel(offset: 2, function: ChannelFunction.blue),
  ],
);

PatchedFixture _fx(String id, FixtureProfile p, int start, double x) =>
    PatchedFixture(id: id, label: id, profile: p, universeId: 'u', startChannel: start, layoutX: x, layoutY: 0.2);

class _Shows implements LiveShowHost {
  final started = <String, LiveShowRef>{};
  final stopped = <String>[];

  @override
  void start(LiveLane lane, LiveShowRef show) => started[lane.id] = show;

  @override
  void stop(LiveLane lane) {
    stopped.add(lane.id);
    started.remove(lane.id);
  }

  @override
  bool isPlaying(LiveLane lane) => started.containsKey(lane.id);
}

class _Out implements LiveOutput {
  final values = <String, Map<int, int>>{};
  final buffer = List<int>.filled(512, 0);
  final claimed = <String>[];
  final released = <String>[];

  @override
  void claimLayer(String layer) => claimed.add(layer);

  @override
  void setLayerChannel(UniverseConfig universe, int channel, int value, String layer) {
    values.putIfAbsent(layer, () => {})[channel] = value;
    buffer[channel] = value;
  }

  @override
  void releaseLayer(String layer) {
    released.add(layer);
    values.remove(layer);
  }

  @override
  void flush(UniverseConfig universe) {}

  @override
  int getChannelValue(UniverseConfig universe, int channel) => buffer[channel];
}

void main() {
  final fixtures = [
    _fx('h1', _head, 0, 0.3),
    _fx('h2', _head, 10, 0.7),
    _fx('p1', _par, 20, 0.2),
    _fx('p2', _par, 23, 0.8),
  ];
  final rig = LiveRig(fixtures: fixtures, universes: const [_universe]);

  late _Out out;
  var clock = 0.0;

  /// Ticks in 25 ms steps up to [seconds], the way the app does.
  void runTo(LiveEngine e, double seconds) {
    while (clock + 0.025 <= seconds + 1e-9) {
      clock += 0.025;
      e.tick(clock);
    }
  }

  late LiveGrid grid;
  late LiveEngine engine;

  setUp(() {
    out = _Out();
    clock = 0;
    grid = LiveGrid.starter();
    engine = LiveEngine(output: out, grid: () => grid, rig: () => rig, fallbackBpm: () => 120);
  });

  group('targets', () {
    test('heads, pars and all pick the right fixtures, left to right', () {
      LiveLane lane(LiveLaneKind k, LiveTargetKind t) => LiveLane(id: 'x', name: 'x', kind: k, target: t);
      expect(targetsOf(lane(LiveLaneKind.moves, LiveTargetKind.all), rig).map((f) => f.id), ['h1', 'h2']);
      expect(targetsOf(lane(LiveLaneKind.colors, LiveTargetKind.pars), rig).map((f) => f.id), ['p1', 'p2']);
      expect(targetsOf(lane(LiveLaneKind.colors, LiveTargetKind.heads), rig), isEmpty);
      expect(targetsOf(lane(LiveLaneKind.level, LiveTargetKind.all), rig).map((f) => f.id), ['p1', 'h1', 'h2', 'p2']);
    });
  });

  group('select + GO', () {
    test('a tap only marks NEXT; GO on bar starts it at the next bar', () {
      engine.tick(0);
      engine.select('colors-pars', 0, mode: LivePadMode.selectThenGo, quantize: LiveQuantize.bar);
      expect(engine.status.queued, {'colors-pars': 0});
      runTo(engine, 1);
      expect(engine.status.running, isEmpty);

      engine.go(quantize: LiveQuantize.bar);
      expect(engine.status.armedAt['colors-pars'], 4);
      runTo(engine, 1.9); // beat 3.8
      expect(engine.status.running, isEmpty);
      runTo(engine, 2.05); // beat 4.1
      expect(engine.status.running, {'colors-pars': 0});
      expect(engine.status.queued, isEmpty);
      expect(out.claimed, contains(liveLayerId('colors-pars')));
    });

    test('a second tap clears the selection', () {
      engine.select('moves', 1, mode: LivePadMode.selectThenGo, quantize: LiveQuantize.bar);
      engine.select('moves', 1, mode: LivePadMode.selectThenGo, quantize: LiveQuantize.bar);
      expect(engine.status.queued, isEmpty);
    });

    test('launch directly arms on its own and GO now starts at once', () {
      engine.tick(0);
      runTo(engine, 0.2); // beat 0.4
      engine.select('level', 2, mode: LivePadMode.launchDirectly, quantize: LiveQuantize.beat);
      expect(engine.status.armedAt['level'], 1);
      runTo(engine, 0.55);
      expect(engine.status.running, {'level': 2});

      engine.select('beam', 0, mode: LivePadMode.selectThenGo, quantize: LiveQuantize.now);
      engine.go(quantize: LiveQuantize.now);
      expect(engine.status.running['beam'], 0);
    });

    test('a scene row selects every lane that has a clip in it', () {
      engine.selectRow(1, mode: LivePadMode.selectThenGo, quantize: LiveQuantize.bar);
      expect(engine.status.queued.keys.toSet(), {'moves', 'colors-heads', 'colors-pars', 'level'});
    });

    test('stop releases the lane layer', () {
      engine.select('level', 0, mode: LivePadMode.launchDirectly, quantize: LiveQuantize.now);
      engine.go(quantize: LiveQuantize.now);
      engine.stopLane('level');
      expect(engine.status.running, isEmpty);
      expect(out.released, contains(liveLayerId('level')));
      expect(out.released, contains(liveShutterLayer));
    });
  });

  group('output', () {
    test('a colour clip writes the pars only, on its own layer', () {
      grid = grid.withClip('colors-pars', 0, const LiveClip(name: 'Red', colors: LiveColorFx(colors: [0xFF0000])));
      engine.select('colors-pars', 0, mode: LivePadMode.selectThenGo, quantize: LiveQuantize.now);
      engine.go(quantize: LiveQuantize.now);
      engine.tick(0);
      engine.tick(0.1);
      final written = out.values[liveLayerId('colors-pars')]!;
      expect(written[20], 255);
      expect(written[21], 0);
      expect(written[23], 255);
      expect(written.keys.every((ch) => ch >= 20), isTrue);
    });

    test('a level lane dims heads, opens their shutter and scales dimmer-less pars', () {
      grid = grid
          .withClip('level', 0, const LiveClip(name: 'Half', level: LiveLevelFx(high: 0.5)))
          .withClip('colors-pars', 0, const LiveClip(name: 'White', colors: LiveColorFx(colors: [0xFFFFFF])));
      for (final lane in ['level', 'colors-pars']) {
        engine.select(lane, 0, mode: LivePadMode.selectThenGo, quantize: LiveQuantize.now);
      }
      engine.go(quantize: LiveQuantize.now);
      engine.tick(0);
      engine.tick(0.1);
      expect(out.values[liveLayerId('level')]![2], 128); // h1 dimmer
      expect(out.values[liveShutterLayer]![3], 5); // h1 shutter open slot
      expect(out.values[liveLayerId('colors-pars')]![20], 128); // white at half
    });

    test('a beam lane strobes inside the strobe range', () {
      grid = grid.withClip('beam', 0, const LiveClip(name: 'S', beam: LiveBeamFx(strobe: 1, gobo: 40)));
      engine.select('beam', 0, mode: LivePadMode.selectThenGo, quantize: LiveQuantize.now);
      engine.go(quantize: LiveQuantize.now);
      engine.tick(0);
      engine.tick(0.1);
      expect(out.values[liveLayerId('beam')]![3], 215);
      expect(out.values[liveLayerId('beam')]![4], 40);
    });

    test('moves glide in and then follow the shape', () {
      grid = grid.withClip(
        'moves',
        0,
        const LiveClip(name: 'C', moves: MovementFx(shape: MovementShape.circle, sizePanDeg: 30, sizeTiltDeg: 30, beatLocked: true, beats: 4)),
      );
      engine.select('moves', 0, mode: LivePadMode.selectThenGo, quantize: LiveQuantize.now);
      engine.go(quantize: LiveQuantize.now);
      engine.tick(0);
      engine.tick(0.01);
      final early = out.values[liveLayerId('moves')]![0]!;
      expect(early, lessThan(40)); // still near where the head was (0)
      clock = 0.01;
      runTo(engine, 1);
      final later = out.values[liveLayerId('moves')]![0]!;
      expect(later, greaterThan(100)); // round the middle of the pan range
    });

    test('freeze holds the clock', () {
      engine.tick(0);
      runTo(engine, 1);
      final beat = engine.status.beat;
      engine.setFrozen(true);
      runTo(engine, 2);
      expect(engine.status.beat, beat);
    });
  });

  group('clock', () {
    test('beats set the tempo and pull the count onto the beat', () {
      engine.tick(0);
      engine.onBeat(0.0);
      engine.tick(0.4);
      engine.onBeat(0.4); // 150 BPM
      expect(engine.status.bpm, closeTo(150, 0.01));
      engine.tick(0.8);
      engine.onBeat(0.8);
      expect(engine.status.beat - engine.status.beat.roundToDouble(), closeTo(0, 0.2));
    });

    test('markDownbeat makes the current beat the first of the bar', () {
      engine.tick(0);
      runTo(engine, 1.5); // beat 3
      engine.markDownbeat();
      expect(engine.status.beatInBar, 1);
    });
  });

  group('patterns', () {
    test('level patterns stay in range and chase lights one at a time', () {
      for (final p in LiveLevelPattern.values) {
        for (var b = 0.0; b < 4; b += 0.13) {
          final v = levelValue(LiveLevelFx(pattern: p, low: 0.2, high: 0.9, beats: 2), b, 1, 3);
          expect(v, inInclusiveRange(0.2, 0.9));
        }
      }
      const chase = LiveLevelFx(pattern: LiveLevelPattern.chase, low: 0, high: 1, beats: 1);
      expect([for (var i = 0; i < 3; i++) levelValue(chase, 1.5, i, 3)], [0, 1, 0]);
    });

    test('colour patterns', () {
      const two = [0xFF0000, 0x0000FF];
      expect(colorValue(const LiveColorFx(pattern: LiveColorPattern.step, colors: two), 0.5, 0, 2), 0xFF0000);
      expect(colorValue(const LiveColorFx(pattern: LiveColorPattern.step, colors: two), 1.5, 0, 2), 0x0000FF);
      expect(colorValue(const LiveColorFx(pattern: LiveColorPattern.alternate, colors: two), 0.5, 1, 2), 0x0000FF);
      final mid = colorValue(const LiveColorFx(pattern: LiveColorPattern.step, colors: two, fade: 1), 0.5, 0, 2);
      expect((mid >> 16) & 255, inInclusiveRange(100, 155));
      expect(colorValue(const LiveColorFx(pattern: LiveColorPattern.rainbow), 0, 0, 1), 0xFF0000);
    });
  });

  group('model', () {
    test('the grid survives a JSON round trip', () {
      final starter = LiveGrid.starter();
      final back = LiveGrid.fromJson(starter.toJson());
      expect(back.lanes.length, starter.lanes.length);
      expect(back.rows, starter.rows);
      expect(back.cells.keys.toSet(), starter.cells.keys.toSet());
      expect(back.clipAt('colors-heads', 2)!.colors!.colors, [0xFF0000, 0xFFFFFF]);
      expect(back.clipAt('moves', 0)!.moves!.shape, MovementShape.circle);
      expect(back.clipAt('beam', 2)!.beam!.strobe, 0.6);
    });
  });

  group('Bank / Chase / Scene clips', () {
    late _Shows shows;
    setUp(() {
      shows = _Shows();
      engine = LiveEngine(output: out, grid: () => grid, rig: () => rig, fallbackBpm: () => 120, shows: shows);
    });

    test('a Show lane clip starts on GO and stops with the lane', () {
      const bank = LiveShowRef(kind: LiveShowKind.bank, id: 'b1');
      grid = grid.withClip('show', 0, const LiveClip(name: 'Bank 1', show: bank));
      engine.tick(0);
      engine.select('show', 0, mode: LivePadMode.selectThenGo, quantize: LiveQuantize.now);
      expect(shows.started, isEmpty);
      engine.go(quantize: LiveQuantize.now);
      expect(shows.started, {'show': bank});
      expect(engine.status.running, {'show': 0});
      expect(out.claimed, isNot(contains(liveLayerId('show'))));
      engine.stopLane('show');
      expect(shows.stopped, ['show']);
      expect(engine.status.running, isEmpty);
    });

    test('any lane can hold one; switching back to an effect stops it', () {
      const chase = LiveShowRef(kind: LiveShowKind.chase, id: 'c1');
      grid = grid.withClip('colors-pars', 4, const LiveClip(name: 'My chase', show: chase));
      engine.tick(0);
      engine.select('colors-pars', 4, mode: LivePadMode.launchDirectly, quantize: LiveQuantize.now);
      engine.go(quantize: LiveQuantize.now);
      expect(shows.started, {'colors-pars': chase});
      runTo(engine, 0.5);
      // The engine writes nothing of its own for that lane.
      expect(out.values[liveLayerId('colors-pars')], isNull);

      engine.select('colors-pars', 0, mode: LivePadMode.launchDirectly, quantize: LiveQuantize.now);
      engine.go(quantize: LiveQuantize.now);
      runTo(engine, 0.6);
      expect(shows.stopped, ['colors-pars']);
      expect(out.values[liveLayerId('colors-pars')], isNotEmpty);
    });

    test('stopped from elsewhere: the lane stops counting as running', () {
      grid = grid.withClip('show', 1, const LiveClip(name: 'S', show: LiveShowRef(kind: LiveShowKind.scene, id: 's1')));
      engine.tick(0);
      engine.select('show', 1, mode: LivePadMode.launchDirectly, quantize: LiveQuantize.now);
      engine.go(quantize: LiveQuantize.now);
      shows.started.clear(); // e.g. Dashboard Stop
      runTo(engine, 0.5);
      expect(engine.status.running, {'show': 1}); // grace period
      runTo(engine, 1.2);
      expect(engine.status.running, isEmpty);
    });

    test('show clips and lane layers survive JSON', () {
      final g = LiveGrid.starter()
          .addLane(const LiveLane(id: 'show-2', name: 'Show', kind: LiveLaneKind.show, layerId: 'layer-2'))
          .withClip('show-2', 0, const LiveClip(name: 'X', show: LiveShowRef(kind: LiveShowKind.chase, id: 'c9')));
      final back = LiveGrid.fromJson(g.toJson());
      expect(back.lane('show-2')!.layerId, 'layer-2');
      expect(back.clipAt('show-2', 0)!.show, const LiveShowRef(kind: LiveShowKind.chase, id: 'c9'));
      expect(back.removeLane('show-2').clipAt('show-2', 0), isNull);
      expect(back.freeLaneId('show'), 'show-3');
    });
  });
}
