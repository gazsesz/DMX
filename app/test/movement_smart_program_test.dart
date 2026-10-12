import 'dart:async';

import 'package:dmx_controller/core/artnet/artnet_service.dart';
import 'package:dmx_controller/core/audio/beat_source.dart';
import 'package:dmx_controller/core/playback/chase_player.dart';
import 'package:dmx_controller/core/playback/smart_program_player.dart';
import 'package:dmx_controller/models/artnet_settings.dart';
import 'package:dmx_controller/models/bank.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/layer.dart';
import 'package:dmx_controller/models/movement_fx.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/smart_program.dart';
import 'package:dmx_controller/models/universe_config.dart';
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

void main() {
  const universe = UniverseConfig(id: 'u1', name: 'Universe 1', universe: 0);
  const mover = FixtureProfile(
    id: 'mover',
    name: 'Mover',
    category: FixtureCategory.movingHead,
    channels: [
      FixtureChannel(offset: 0, function: ChannelFunction.pan),
      FixtureChannel(offset: 1, function: ChannelFunction.tilt),
    ],
  );
  const head = PatchedFixture(id: 'head', label: 'Head', profile: mover, universeId: 'u1', startChannel: 0);
  final fxBank = Bank(
    id: 'fx',
    name: 'Circle',
    sceneSlots: const [],
    fx: const MovementFx(periodSec: 1, sizePanDeg: 90),
  );

  test('a Smart Program plays a Movement FX bank on its layer and keeps it running', () async {
    final service = ArtNetService();
    await service.connect(const ArtNetSettings(demoMode: true));
    final players = <String, ChasePlayer>{};
    final smart = SmartProgramPlayer(
      playerFor: (id) => players.putIfAbsent(id, ChasePlayer.new),
      beatService: _FakeBeatSource(),
    );
    addTearDown(() async {
      smart.dispose();
      await service.disconnect();
    });

    final program = const SmartProgram(id: 'p', name: 'Move', baseBankId: 'fx').withLayerTargets([
      LayerZoneTargets(layerId: layer1Id, base: ProgramTarget.from(bankId: 'fx')),
    ]);
    await smart.start(
      program: program,
      chases: const [],
      scenes: const [],
      banks: [fxBank],
      patchedFixtures: const [head],
      universes: const [universe],
      service: service,
    );

    final seen = <int>{};
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      seen.add(service.getChannelValue(universe, 0));
    }
    expect(players[layer1Id]!.isPlaying, isTrue);
    expect(seen.length, greaterThan(4), reason: 'the pan keeps moving well past a single beat of hold');
  });
}
