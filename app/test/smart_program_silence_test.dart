import 'dart:async';
import 'dart:math' as math;

import 'package:dmx_controller/core/artnet/artnet_service.dart';
import 'package:dmx_controller/core/audio/beat_source.dart';
import 'package:dmx_controller/core/audio/tempo_estimator.dart';
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

/// Random onsets the way a quiet room produces them: Poisson arrivals at
/// [perSecond], with the detector's own 250 ms refractory period.
List<Duration> _noise(math.Random rng, double perSecond, Duration length) {
  final out = <Duration>[];
  var t = 0.0;
  while (true) {
    t += -math.log(1 - rng.nextDouble()) / perSecond * 1000;
    if (t >= length.inMilliseconds) return out;
    if (out.isEmpty || t - out.last.inMicroseconds / 1000 > 250) out.add(Duration(microseconds: (t * 1000).round()));
  }
}

List<Duration> _steady(double bpm, Duration from, Duration length) {
  final period = 60000 / bpm;
  return [
    for (var t = 0.0; t < length.inMilliseconds; t += period)
      from + Duration(microseconds: (t * 1000).round()),
  ];
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
  Bank fx(String id) => Bank(id: id, name: id, sceneSlots: const [], fx: const MovementFx(periodSec: 1, sizePanDeg: 90));
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

  group('estimateTempo is fooled by random onsets, isSteadyPulse is not', () {
    test('random onsets fold into a "confident" tempo but are no steady pulse', () {
      final rng = math.Random(7);
      final t0 = DateTime(2026);
      var confident = 0;
      var steady = 0;
      for (var i = 0; i < 200; i++) {
        final beats = [for (final d in _noise(rng, 3, const Duration(seconds: 30)).take(12)) t0.add(d)];
        final estimate = estimateTempo(beats);
        if (estimate != null && estimate.isConfident) confident++;
        if (isSteadyPulse(beats, estimate)) steady++;
      }
      expect(confident, greaterThan(140), reason: 'this is the bug: noise reads as a tempo');
      expect(steady, lessThan(20));
    });

    test('a real track with missed kicks and stray hits is still a steady pulse', () {
      final rng = math.Random(3);
      final t0 = DateTime(2026);
      var steady = 0;
      for (var i = 0; i < 200; i++) {
        final beats = <DateTime>[];
        var k = 0;
        while (beats.length < 12) {
          k++;
          final ms = k * 60000 / 128 + (rng.nextDouble() - 0.5) * 30;
          if (rng.nextDouble() > 0.2) beats.add(t0.add(Duration(microseconds: (ms * 1000).round())));
          if (rng.nextDouble() < 0.08) beats.add(t0.add(Duration(microseconds: ((ms + 60000 / 128 * 0.5) * 1000).round())));
        }
        beats.sort();
        if (isSteadyPulse(beats, estimateTempo(beats))) steady++;
      }
      expect(steady, greaterThan(150));
    });

    test('a clean pulse is fully regular, and the grid follows the beats, not the octave-corrected tempo', () {
      final t0 = DateTime(2026);
      // 32 BPM: estimateTempo reports it doubled into range.
      final slow = [for (var i = 0; i < 12; i++) t0.add(Duration(microseconds: (i * 60000000 / 32).round()))];
      final estimate = estimateTempo(slow)!;
      expect(estimate.bpm, closeTo(64, 1));
      expect(pulseRegularity(slow, estimate.pulseBpm), 1.0);
      expect(isSteadyPulse(slow, estimate), isTrue);
    });

    test('a pulse at the detector\'s own 250 ms limit is not believed', () {
      final t0 = DateTime(2026);
      final capped = [for (var i = 0; i < 12; i++) t0.add(Duration(milliseconds: i * 260))];
      final estimate = estimateTempo(capped)!;
      expect(pulseRegularity(capped, estimate.pulseBpm), 1.0);
      expect(isSteadyPulse(capped, estimate), isFalse);
    });
  });

  group('a Smart Program with no music', () {
    test('random onsets never switch it to Faster, and it blacks out', () {
      fakeAsync((async) {
        final rng = math.Random(11);
        final result = run(async, _noise(rng, 3.5, const Duration(seconds: 40)));
        expect(result.statuses.where((s) => s.zone == SmartProgramZone.faster), isEmpty);
        final firstSilent = result.statuses.indexWhere((s) => s.isSilent);
        expect(firstSilent, isNot(-1), reason: 'no steady pulse for 10 s is no music');
        expect(result.smart.currentZone, isNot(SmartProgramZone.faster));
        result.smart.dispose();
      });
    });

    test('noise after silence does not bring the show back; a real pulse does', () {
      fakeAsync((async) {
        final rng = math.Random(5);
        final noise = _noise(rng, 3, const Duration(seconds: 25));
        final music = _steady(122, const Duration(seconds: 26), const Duration(seconds: 12));
        final result = run(async, [...noise, ...music]);
        final silentAt = result.statuses.indexWhere((s) => s.isSilent);
        expect(silentAt, isNot(-1));
        final after = result.statuses.sublist(silentAt + 1);
        expect(after.where((s) => !s.isSilent && s.zone == SmartProgramZone.slower), isNotEmpty);
        expect(after.where((s) => s.zone == SmartProgramZone.faster), isEmpty);
        result.smart.dispose();
      });
    });
  });

  group('a Smart Program with music', () {
    test('a steady fast song still switches to Faster after its hold', () {
      fakeAsync((async) {
        final result = run(async, _steady(140, Duration.zero, const Duration(seconds: 12)));
        expect(result.smart.currentZone, SmartProgramZone.faster);
        expect(result.statuses.where((s) => s.isSilent), isEmpty);
        result.smart.dispose();
      });
    });

    test('a steady base-tempo song never blacks out', () {
      fakeAsync((async) {
        final result = run(async, _steady(120, Duration.zero, const Duration(seconds: 40)), tail: Duration.zero);
        expect(result.statuses.where((s) => s.isSilent), isEmpty);
        expect(result.smart.currentZone, SmartProgramZone.base);
        result.smart.dispose();
      });
    });

    test('when the music stops dead it blacks out after 4 s, as before', () {
      fakeAsync((async) {
        final result = run(async, _steady(120, Duration.zero, const Duration(seconds: 10)), tail: const Duration(seconds: 5));
        expect(result.statuses.last.isSilent, isTrue);
        result.smart.dispose();
      });
    });
  });
}
