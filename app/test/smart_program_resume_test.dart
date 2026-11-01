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
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBeatSource implements BeatSource {
  final _controller = StreamController<DateTime>.broadcast();

  void beat(DateTime at) => _controller.add(at);

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
  Bank fx(String id) =>
      Bank(id: id, name: id, sceneSlots: const [], fx: const MovementFx(periodSec: 1, sizePanDeg: 90));
  final banks = [fx('base'), fx('fast'), fx('slow')];
  // Base 120 BPM: faster from 132, slower from 108.
  final program = const SmartProgram(id: 'p', name: 'P').withLayerTargets([
    LayerZoneTargets(
      layerId: layer1Id,
      base: ProgramTarget.from(bankId: 'base'),
      faster: ProgramTarget.from(bankId: 'fast'),
      slower: ProgramTarget.from(bankId: 'slow'),
    ),
  ]);

  /// Runs [beats] (offsets from the start) through a running program and
  /// returns every status it reported, plus the player for a final look.
  ({List<SmartProgramStatus> statuses, SmartProgramPlayer smart}) run(
    FakeAsync async,
    List<Duration> beats, {
    Duration tail = const Duration(seconds: 2),
  }) {
    final service = ArtNetService();
    service.connect(const ArtNetSettings(demoMode: true));
    final source = _FakeBeatSource();
    final players = <String, ChasePlayer>{};
    final smart = SmartProgramPlayer(playerFor: (id) => players.putIfAbsent(id, ChasePlayer.new), beatService: source);
    final statuses = <SmartProgramStatus>[];
    smart.statusStream.listen(statuses.add);
    smart.start(
      program: program,
      chases: const [],
      scenes: const [],
      banks: banks,
      patchedFixtures: const [head],
      universes: const [universe],
      service: service,
    );
    async.flushMicrotasks();
    final t0 = DateTime(2026, 11, 1, 12);
    var elapsed = Duration.zero;
    for (final at in beats) {
      async.elapse(at - elapsed);
      elapsed = at;
      source.beat(t0.add(at));
      async.flushMicrotasks();
    }
    async.elapse(tail);
    return (statuses: statuses, smart: smart);
  }


  List<Duration> steady(Duration from, int count, {int gapMs = 500}) =>
      [for (var i = 0; i < count; i++) from + Duration(milliseconds: i * gapMs)];

  test('music, then silence: blacks out after 4 s', () {
    fakeAsync((async) {
      final r = run(async, steady(Duration.zero, 8), tail: const Duration(seconds: 6));
      expect(r.statuses.last.isSilent, isTrue);
    });
  });

  test('a cough or a click in the blackout does not bring it back', () {
    fakeAsync((async) {
      final beats = [
        ...steady(Duration.zero, 8),
        const Duration(seconds: 10), // cough
        const Duration(seconds: 13), // click
        const Duration(milliseconds: 13100), // a double click, too close
        const Duration(seconds: 16),
      ];
      final r = run(async, beats);
      expect(r.statuses.last.isSilent, isTrue);
    });
  });

  test('three beats of music are not enough, the fourth brings it back on Slower', () {
    fakeAsync((async) {
      final three = run(async, [...steady(Duration.zero, 8), ...steady(const Duration(seconds: 10), 3)],
          tail: const Duration(milliseconds: 100));
      expect(three.statuses.last.isSilent, isTrue);
    });
    fakeAsync((async) {
      final four = run(async, [...steady(Duration.zero, 8), ...steady(const Duration(seconds: 10), 4)],
          tail: const Duration(milliseconds: 100));
      expect(four.statuses.last.isSilent, isFalse);
      expect(four.statuses.last.zone, SmartProgramZone.slower);
    });
  });
}
