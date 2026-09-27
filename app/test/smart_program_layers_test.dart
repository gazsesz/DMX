import 'dart:async';

import 'package:dmx_controller/core/artnet/artnet_service.dart';
import 'package:dmx_controller/core/audio/beat_source.dart';
import 'package:dmx_controller/core/playback/chase_player.dart';
import 'package:dmx_controller/core/playback/smart_layer_display.dart';
import 'package:dmx_controller/core/playback/smart_program_player.dart';
import 'package:dmx_controller/models/artnet_settings.dart';
import 'package:dmx_controller/models/bank.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/chase.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/layer.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/scene.dart';
import 'package:dmx_controller/models/smart_program.dart';
import 'package:dmx_controller/models/universe_config.dart';
import 'package:dmx_controller/state/playback_providers.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBeatSource implements BeatSource {
  final _controller = StreamController<DateTime>.broadcast();

  @override
  Stream<DateTime> get beatEvents => _controller.stream;
  @override
  bool get isListening => true;
  @override
  String? get lastError => null;
  @override
  Future<bool> start() async => true;
  @override
  Future<void> stop() async {}
}

const _l2 = 'layer-2';
const _l3 = 'layer-3';

void main() {
  group('chase lanes', () {
    const existing = [layer1Id, _l2, _l3];

    test('a step with no layer plays on Layer 1', () {
      expect(laneOf(const ChaseStep(sceneId: 's'), existing), layer1Id);
    });

    test('a step whose layer was deleted falls back to Layer 1', () {
      expect(laneOf(const ChaseStep(sceneId: 's', layerId: 'gone'), existing), layer1Id);
    });

    test('splits steps by layer, keeping each lane in order and lanes in layer order', () {
      const chase = Chase(
        id: 'c',
        name: 'Build',
        steps: [
          ChaseStep(bankId: 'robot-a', layerId: _l2),
          ChaseStep(bankId: 'rgb-a'),
          ChaseStep(bankId: 'robot-b', layerId: _l2),
          ChaseStep(bankId: 'rgb-b'),
        ],
      );
      final lanes = chaseLanes(chase, existing);
      expect(lanes.keys, [layer1Id, _l2]);
      expect(lanes[layer1Id]!.steps.map((s) => s.bankId), ['rgb-a', 'rgb-b']);
      expect(lanes[_l2]!.steps.map((s) => s.bankId), ['robot-a', 'robot-b']);
    });

    test('a step keeps its layer through a timing edit and JSON', () {
      const step = ChaseStep(sceneId: 's', layerId: _l2);
      expect(step.copyWith(hold: const Duration(seconds: 2)).layerId, _l2);
      expect(ChaseStep.fromJson(step.toJson()).layerId, _l2);
      expect(const ChaseStep(sceneId: 's').toJson().containsKey('layerId'), isFalse);
    });
  });

  group('Smart Program layer targets', () {
    test('an old, single-layer program loads as Layer 1 only', () {
      final program = SmartProgram.fromJson({'id': 'p', 'name': 'Old', 'baseBankId': 'b1', 'fasterChaseId': 'c1'});
      expect(program.drivenLayers.map((l) => l.layerId), [layer1Id]);
      expect(program.targetsFor(layer1Id).base, ProgramTarget.from(bankId: 'b1'));
    });

    test('extra layers round-trip through JSON alongside Layer 1', () {
      final program = const SmartProgram(id: 'p', name: 'Club').withLayerTargets([
        LayerZoneTargets(layerId: layer1Id, base: ProgramTarget.from(bankId: 'rgb')),
        LayerZoneTargets(layerId: _l2, faster: ProgramTarget.from(chaseId: 'robot-fast')),
      ]);
      final restored = SmartProgram.fromJson(program.toJson());
      expect(restored.targetsFor(layer1Id).base, ProgramTarget.from(bankId: 'rgb'));
      expect(restored.targetsFor(_l2).faster, ProgramTarget.from(chaseId: 'robot-fast'));
      expect(restored.targetsFor(_l2).base, isNull);
    });

    test('a zone left empty on a layer falls back to that layer\'s Base', () {
      final targets = LayerZoneTargets(layerId: layer1Id, base: ProgramTarget.from(bankId: 'rgb'));
      expect(targets.effective(SmartProgramZone.faster), ProgramTarget.from(bankId: 'rgb'));
      expect(targets.fallsBackToBase(SmartProgramZone.faster), isTrue);
    });

    test('a layer with no Base sits out the zones it has nothing for', () {
      final targets = LayerZoneTargets(layerId: _l2, faster: ProgramTarget.from(bankId: 'robot'));
      expect(targets.effective(SmartProgramZone.base), isNull);
      expect(targets.effective(SmartProgramZone.faster), ProgramTarget.from(bankId: 'robot'));
    });

    test('Faster is only reachable when some layer has a Faster pick', () {
      final base = const SmartProgram(id: 'p', name: 'P', baseBankId: 'b');
      expect(base.hasFasterTarget, isFalse);
      final withL2 = base.withLayerTargets([
        ...base.layers,
        LayerZoneTargets(layerId: _l2, faster: ProgramTarget.from(bankId: 'x')),
      ]);
      expect(withL2.hasFasterTarget, isTrue);
    });

    test('the idle line says which zones a Base-less layer joins in', () {
      final program = const SmartProgram(id: 'p', name: 'P', baseBankId: 'rgb').withLayerTargets([
        LayerZoneTargets(layerId: layer1Id, base: ProgramTarget.from(bankId: 'rgb')),
        LayerZoneTargets(layerId: _l2, faster: ProgramTarget.from(bankId: 'robot')),
      ]);
      final lines = smartLayerLines(
        program,
        zone: null,
        layers: const [
          Layer(id: layer1Id, name: 'Layer 1', priority: 1),
          Layer(id: _l2, name: 'Layer 2', priority: 2),
        ],
        chases: const [],
        banks: const [
          Bank(id: 'rgb', name: 'RGB Wave', sceneSlots: []),
          Bank(id: 'robot', name: 'Robot Fast', sceneSlots: []),
        ],
      );
      expect(lines.first.targetName, 'RGB Wave');
      expect(lines.last.targetName, isNull);
      expect(lines.last.onlyIn, 'Faster');
    });
  });

  group('SmartProgramPlayer across layers', () {
    const universe = UniverseConfig(id: 'u1', name: 'U1', universe: 0);
    final profile = FixtureProfile(
      id: 'rgb',
      name: 'RGB',
      category: FixtureCategory.generic,
      channels: const [
        FixtureChannel(offset: 0, function: ChannelFunction.red),
        FixtureChannel(offset: 1, function: ChannelFunction.green),
        FixtureChannel(offset: 2, function: ChannelFunction.blue),
      ],
    );
    final par = PatchedFixture(id: 'par', label: 'Par', profile: profile, universeId: 'u1', startChannel: 0);
    final head = PatchedFixture(id: 'head', label: 'Head', profile: profile, universeId: 'u1', startChannel: 10);
    const scenes = [
      Scene(id: 'red', name: 'Red', fixtureValues: {'par': {0: 255}}),
      Scene(id: 'blue', name: 'Blue', fixtureValues: {'head': {2: 255}}),
    ];
    const banks = [
      Bank(id: 'b-red', name: 'Red', sceneSlots: ['red']),
      Bank(id: 'b-blue', name: 'Blue', sceneSlots: ['blue']),
    ];

    late ArtNetService service;
    late Map<String, ChasePlayer> players;
    late SmartProgramPlayer smart;

    setUp(() async {
      service = ArtNetService();
      await service.connect(const ArtNetSettings(demoMode: true));
      players = {};
      smart = SmartProgramPlayer(
        playerFor: (id) => players.putIfAbsent(id, ChasePlayer.new),
        beatService: _FakeBeatSource(),
      );
    });

    tearDown(() async {
      smart.dispose();
      await service.disconnect();
    });

    Future<void> start(SmartProgram program) => smart.start(
      program: program,
      chases: const [],
      scenes: scenes,
      banks: banks,
      patchedFixtures: [par, head],
      universes: const [universe],
      service: service,
    );

    // Layer 1 plays red at Base; Layer 2 only has a Faster pick.
    final program = const SmartProgram(id: 'p', name: 'Club', baseBankId: 'b-red').withLayerTargets([
      LayerZoneTargets(layerId: layer1Id, base: ProgramTarget.from(bankId: 'b-red')),
      LayerZoneTargets(layerId: _l2, faster: ProgramTarget.from(bankId: 'b-blue')),
    ]);

    test('at Base each layer plays its own pick, and a layer with none stays dark', () async {
      await start(program);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(players[layer1Id]!.isPlaying, isTrue);
      expect(players[_l2]?.isPlaying ?? false, isFalse);
      expect(service.getChannelValue(universe, 0), greaterThan(0), reason: 'Layer 1 red fading up on the par');
      expect(service.getChannelValue(universe, 12), 0, reason: 'Layer 2 has nothing at Base');
      expect(smart.drivenLayerIds, [layer1Id, _l2]);
    });

    test('taking one layer back leaves the program running on the others', () async {
      await start(program);
      expect(smart.releaseLayer(layer1Id), isFalse);
      expect(smart.isRunning, isTrue);
      expect(players[layer1Id]!.isPlaying, isFalse);
      expect(smart.drivenLayerIds, [_l2]);
      expect(smart.releaseLayer(_l2), isTrue, reason: 'the last layer taken back ends the program');
      expect(smart.isRunning, isFalse);
    });

    test('stopping the program stops every layer it drove', () async {
      await start(program);
      smart.stop();
      expect(players[layer1Id]!.isPlaying, isFalse);
      expect(smart.drivenLayerIds, isEmpty);
    });
  });
}
