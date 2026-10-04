import 'dart:async';

import 'package:dmx_controller/core/artnet/artnet_service.dart';
import 'package:dmx_controller/core/audio/beat_source.dart';
import 'package:dmx_controller/core/playback/chase_player.dart';
import 'package:dmx_controller/core/playback/smart_program_player.dart';
import 'package:dmx_controller/models/artnet_settings.dart';
import 'package:dmx_controller/models/bank.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/chase.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/layer.dart';
import 'package:dmx_controller/models/scene.dart';
import 'package:dmx_controller/models/smart_program.dart';
import 'package:dmx_controller/models/universe_config.dart';
import 'package:dmx_controller/state/dimmer_dropout_providers.dart';
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
const _blips = DropoutSettings(enabled: true, lengthMs: 90, intervalMs: 3000);

void main() {
  beatAndChaseTests();
  final program = const SmartProgram(id: 'p', name: 'Club').withLayerTargets([
    LayerZoneTargets(layerId: layer1Id, base: ProgramTarget.from(bankId: 'b-red')),
    LayerZoneTargets(layerId: _l2, faster: ProgramTarget.from(bankId: 'b-red')),
  ]);

  group('SmartProgram zone dropouts', () {
    test('survive JSON, a layer-target rewrite and a copy', () {
      final withDropout = program.copyWith(zoneDropouts: {SmartProgramZone.faster: _blips});
      final restored = SmartProgram.fromJson(withDropout.toJson());
      expect(restored.zoneDropouts.keys, [SmartProgramZone.faster]);
      expect(restored.zoneDropouts[SmartProgramZone.faster], _blips);
      expect(withDropout.withLayerTargets(withDropout.layers).zoneDropouts, withDropout.zoneDropouts);
      expect(withDropout.duplicateAs('q', 'Copy').zoneDropouts, withDropout.zoneDropouts);
    });

    test('an old program has none, and writes no key for them', () {
      expect(SmartProgram.fromJson({'id': 'p', 'name': 'Old'}).zoneDropouts, isEmpty);
      expect(program.toJson().containsKey('zoneDropouts'), isFalse);
    });
  });

  group('SmartProgramPlayer hands the zone\'s dropout over', () {
    const universe = UniverseConfig(id: 'u1', name: 'U1', universe: 0);
    const scenes = [Scene(id: 'red', name: 'Red', fixtureValues: {})];
    const banks = [Bank(id: 'b-red', name: 'Red', sceneSlots: ['red'])];

    late ArtNetService service;
    late List<DropoutSettings?> handed;
    late SmartProgramPlayer smart;

    setUp(() async {
      service = ArtNetService();
      await service.connect(const ArtNetSettings(demoMode: true));
      handed = [];
      final players = <String, ChasePlayer>{};
      smart = SmartProgramPlayer(
        playerFor: (id) => players.putIfAbsent(id, ChasePlayer.new),
        beatService: _FakeBeatSource(),
        setDropout: handed.add,
      );
    });

    tearDown(() async {
      smart.dispose();
      await service.disconnect();
    });

    Future<void> start(SmartProgram p) => smart.start(
      program: p,
      chases: const [],
      scenes: scenes,
      banks: banks,
      patchedFixtures: const [],
      universes: const [universe],
      service: service,
    );

    test('a program with no dropout leaves the hand-set one alone', () async {
      await start(program);
      expect(handed.where((s) => s != null), isEmpty);
    });

    test('Base\'s dropout is aimed at the layers the program drives', () async {
      await start(program.copyWith(zoneDropouts: {SmartProgramZone.base: _blips}));
      final active = handed.last!;
      expect(active.enabled, isTrue);
      expect(active.targetLayerIds, {layer1Id, _l2});
      expect(active.lengthMs, 90);
    });

    test('a layer list narrows it, and ignores layers the program does not drive', () async {
      final narrowed = _blips.copyWith(targetLayerIds: {_l2, 'not-driven'});
      await start(program.copyWith(zoneDropouts: {SmartProgramZone.base: narrowed}));
      expect(handed.last!.targetLayerIds, {_l2});
    });

    test('a zone without one is held dark-free while the program owns the dropout', () async {
      await start(program.copyWith(zoneDropouts: {SmartProgramZone.faster: _blips}));
      expect(handed.last!.enabled, isFalse, reason: 'Base has none, Faster does');
    });

    test('stopping the program lets go of it', () async {
      await start(program.copyWith(zoneDropouts: {SmartProgramZone.base: _blips}));
      smart.stop();
      expect(handed.last, isNull);
    });
  });

  group('DimmerDropoutController override', () {
    test('a program\'s settings run over the hand-set ones and give way on release', () {
      final service = ArtNetService();
      final controller = DimmerDropoutController(service);
      addTearDown(controller.dispose);

      controller.update(const DropoutSettings(enabled: true, lengthMs: 50));
      expect(service.fastRefresh, isTrue);

      controller.setProgramOverride(const DropoutSettings());
      expect(service.fastRefresh, isFalse, reason: 'program says no dropout in this zone');
      expect(controller.state.lengthMs, 50, reason: 'the hand-set state is untouched');

      controller.setProgramOverride(_blips);
      expect(service.fastRefresh, isTrue);

      controller.setProgramOverride(null);
      expect(service.fastRefresh, isTrue, reason: 'back to the hand-set dropout, still on');

      controller.update(const DropoutSettings());
      expect(service.fastRefresh, isFalse);
    });

    test('the same settings handed over again are not a change', () {
      final service = ArtNetService();
      final controller = DimmerDropoutController(service);
      addTearDown(controller.dispose);
      controller.setProgramOverride(_blips);
      final darkChannels = service.darkChannels;
      controller.setProgramOverride(_blips.copyWith());
      expect(identical(service.darkChannels, darkChannels) || service.darkChannels == darkChannels, isTrue);
    });
  });
}

// ---------------------------------------------------------------------------
// On the beat, and on a chase
// ---------------------------------------------------------------------------

void beatAndChaseTests() {
  const universe = UniverseConfig(id: 'u1', name: 'U1', universe: 0);
  final profile = FixtureProfile(
    id: 'dim',
    name: 'Dimmer',
    category: FixtureCategory.generic,
    channels: const [FixtureChannel(offset: 0, function: ChannelFunction.dimmer)],
  );
  final par = PatchedFixture(id: 'par', label: 'Par', profile: profile, universeId: 'u1', startChannel: 0);
  const scene = Scene(id: 'full', name: 'Full', fixtureValues: {'par': {0: 255}});
  const chaseDropout = DropoutSettings(enabled: true, lengthMs: 70, onBeat: true, beatEvery: 4);
  const chase = Chase(
    id: 'c1',
    name: 'Chase',
    steps: [ChaseStep(sceneId: 'full')],
    dropout: chaseDropout,
  );

  group('DropoutSettings on the beat', () {
    test('round-trips, and a nonsense division falls back to every beat', () {
      final back = DropoutSettings.fromJson(chaseDropout.toJson());
      expect(back.onBeat, isTrue);
      expect(back.beatEvery, 4);
      expect(DropoutSettings.fromJson({'beatEvery': 3}).beatEvery, 1);
      expect(chaseDropout == chaseDropout.copyWith(beatEvery: 2), isFalse);
    });
  });

  group('Chase dropout', () {
    test('survives JSON and a copy, and is cleared on request', () {
      final restored = Chase.fromJson(chase.toJson());
      expect(restored.dropout, chaseDropout);
      expect(chase.copyWith(name: 'x').dropout, chaseDropout);
      expect(chase.copyWith(clearDropout: true).dropout, isNull);
      expect(const Chase(id: 'c', name: 'n', steps: []).toJson().containsKey('dropout'), isFalse);
    });

    test('the player tells the controller when it starts and stops', () async {
      final service = ArtNetService();
      await service.connect(const ArtNetSettings(demoMode: true));
      final told = <(String, DropoutSettings?)>[];
      final player = ChasePlayer(layerId: 'a', onDropout: (layer, s) => told.add((layer, s)));
      unawaited(
        player.play(
          chase: chase,
          scenes: const [scene],
          banks: const [],
          patchedFixtures: [par],
          universes: const [universe],
          service: service,
        ),
      );
      expect(told.first, ('a', chaseDropout));
      player.stop();
      expect(told.last, ('a', null));
      await service.disconnect();
    });

    test('a Smart Program that plays the chase plays its dropout with it', () async {
      final service = ArtNetService();
      await service.connect(const ArtNetSettings(demoMode: true));
      final told = <(String, DropoutSettings?)>[];
      final players = <String, ChasePlayer>{};
      final smart = SmartProgramPlayer(
        playerFor: (id) => players.putIfAbsent(id, () => ChasePlayer(layerId: id, onDropout: (l, s) => told.add((l, s)))),
        beatService: _FakeBeatSource(),
      );
      final program = const SmartProgram(id: 'p', name: 'P').withLayerTargets([
        LayerZoneTargets(layerId: layer1Id, base: ProgramTarget.from(chaseId: 'c1')),
      ]);
      await smart.start(
        program: program,
        chases: const [chase],
        scenes: const [scene],
        banks: const [],
        patchedFixtures: [par],
        universes: const [universe],
        service: service,
      );
      expect(told.where((t) => t.$1 == layer1Id && t.$2 == chaseDropout), isNotEmpty);
      smart.dispose();
      await service.disconnect();
    });
  });

  group('DimmerDropoutController lanes', () {
    test('a beat-locked dropout goes dark on every Nth beat, only on the layer it names', () async {
      final service = ArtNetService();
      final beats = StreamController<DateTime>.broadcast();
      final controller = DimmerDropoutController(
        service,
        beatEvents: () => beats.stream,
        beatsListening: () => true,
      );
      addTearDown(() {
        controller.dispose();
        beats.close();
      });
      service.claimLayer('a');
      service.setLayerChannel(universe, 0, 200, 'a');
      controller.refreshScope([par], const [universe]);

      controller.update(const DropoutSettings(enabled: true, onBeat: true, beatEvery: 2, lengthMs: 40, targetLayerIds: {'a'}));
      Set<int> dark() => service.darkChannels!(universe);

      beats.add(DateTime.now());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(dark(), isEmpty, reason: 'the 1st beat of every 2 does nothing');

      beats.add(DateTime.now());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(dark(), {0});

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(dark(), isEmpty);
    });

    test('a chase\'s dropout runs beside the hand-set one, and only cuts its own layer', () {
      final service = ArtNetService();
      final controller = DimmerDropoutController(service);
      addTearDown(controller.dispose);
      controller.setChaseDropout('a', const DropoutSettings(enabled: true, targetLayerIds: {'other'}));
      expect(service.fastRefresh, isTrue);

      controller.update(const DropoutSettings(enabled: true));
      controller.update(const DropoutSettings());
      expect(service.fastRefresh, isTrue, reason: 'the chase lane is still running');

      controller.setChaseDropout('a', null);
      expect(service.fastRefresh, isFalse);
      expect(service.darkChannels, isNull);
    });
  });
}
