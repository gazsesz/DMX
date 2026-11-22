import 'dart:async';
import 'dart:math';

import 'package:dmx_controller/core/artnet/artnet_service.dart';
import 'package:dmx_controller/core/playback/dimmer_dropout.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/universe_config.dart';
import 'package:dmx_controller/state/dimmer_dropout_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ids = ['a', 'b', 'c', 'd', 'e'];
  const alternate = DropoutSettings(pattern: DropoutPattern.alternate);

  group('DropoutSettings pattern json', () {
    test('an old project is all at once, with the defaults', () {
      final old = DropoutSettings.fromJson({'enabled': true});
      expect(old.pattern, DropoutPattern.together);
      expect(old.grouping, DropoutGrouping.oddEven);
      expect(old.pingPong, isFalse);
      expect(old.randomShare, 0.3);
      expect(old.noRepeat, isTrue);
    });

    test('round-trips, and nonsense falls back', () {
      const s = DropoutSettings(
        pattern: DropoutPattern.random,
        grouping: DropoutGrouping.groups,
        pingPong: true,
        randomShare: 0.55,
        noRepeat: false,
      );
      expect(DropoutSettings.fromJson(s.toJson()), s);
      final odd = DropoutSettings.fromJson({'pattern': 'zigzag', 'grouping': 7, 'randomShare': 0});
      expect(odd.pattern, DropoutPattern.together);
      expect(odd.grouping, DropoutGrouping.oddEven);
      expect(odd.randomShare, DropoutSettings.minRandomShare);
      expect(s == s.copyWith(pingPong: false), isFalse);
    });
  });

  group('dropoutUnits', () {
    test('all at once is one unit, random one per lamp', () {
      expect(dropoutUnits(const DropoutSettings(), ids), [ids]);
      expect(dropoutUnits(const DropoutSettings(pattern: DropoutPattern.random), ids), [
        for (final id in ids) [id],
      ]);
      expect(dropoutUnits(const DropoutSettings(), const []), isEmpty);
    });

    test('taking turns splits in lamp order', () {
      expect(dropoutUnits(alternate, ids), [
        ['a', 'c', 'e'],
        ['b', 'd'],
      ]);
      expect(dropoutUnits(alternate.copyWith(grouping: DropoutGrouping.halves), ids), [
        ['a', 'b', 'c'],
        ['d', 'e'],
      ]);
      expect(dropoutUnits(alternate.copyWith(grouping: DropoutGrouping.oneByOne), ids).length, 5);
    });

    test('groups keep only lamps in scope, in lamp order; too few fall back to odd/even', () {
      final byGroup = alternate.copyWith(grouping: DropoutGrouping.groups);
      expect(
        dropoutUnits(
          byGroup,
          ids,
          groups: [
            ['e', 'a', 'zz'],
            ['zz'],
            ['b', 'c'],
          ],
        ),
        [
          ['a', 'e'],
          ['b', 'c'],
        ],
      );
      expect(dropoutUnits(byGroup, ids, groups: [ids]), dropoutUnits(alternate, ids));
    });

    test('a single lamp takes no turns', () {
      expect(dropoutUnits(alternate, const ['a']), [
        ['a'],
      ]);
    });
  });

  group('DropoutStepper', () {
    test('taking turns cycles, or bounces with ping-pong', () {
      final loop = DropoutStepper(alternate, 3, Random(1));
      expect([for (var i = 0; i < 6; i++) loop.next().single], [0, 1, 2, 0, 1, 2]);
      final bounce = DropoutStepper(alternate.copyWith(pingPong: true), 3, Random(1));
      expect([for (var i = 0; i < 7; i++) bounce.next().single], [0, 1, 2, 1, 0, 1, 2]);
      final two = DropoutStepper(alternate.copyWith(pingPong: true), 2, Random(1));
      expect([for (var i = 0; i < 4; i++) two.next().single], [0, 1, 0, 1]);
    });

    test('random cuts the share, at least one, never the same lamp twice running', () {
      const s = DropoutSettings(pattern: DropoutPattern.random, randomShare: 0.3);
      final stepper = DropoutStepper(s, 10, Random(3));
      var last = <int>{};
      for (var i = 0; i < 100; i++) {
        final pick = stepper.next();
        expect(pick.length, 3);
        expect(pick.intersection(last), isEmpty);
        last = pick;
      }
      expect(DropoutStepper(s.copyWith(randomShare: 0.1), 4, Random(1)).next().length, 1);
    });

    test('random over more than half the lamps tops up from last time', () {
      const s = DropoutSettings(pattern: DropoutPattern.random, randomShare: 0.75);
      final stepper = DropoutStepper(s, 4, Random(5));
      for (var i = 0; i < 20; i++) {
        expect(stepper.next().length, 3);
      }
    });

    test('a shrinking patch keeps the walk in range', () {
      final stepper = DropoutStepper(alternate, 4, Random(1));
      stepper.next();
      stepper.next();
      stepper.next();
      stepper.count = 2;
      expect(stepper.next().single, inInclusiveRange(0, 1));
    });
  });

  group('DimmerDropoutController with a pattern', () {
    const universe = UniverseConfig(id: 'u1', name: 'U1', universe: 0);
    final profile = FixtureProfile(
      id: 'dim',
      name: 'Dimmer',
      category: FixtureCategory.generic,
      channels: const [FixtureChannel(offset: 0, function: ChannelFunction.dimmer)],
    );
    final pars = [
      for (var i = 0; i < 4; i++)
        PatchedFixture(id: 'p$i', label: 'Par $i', profile: profile, universeId: 'u1', startChannel: i),
    ];

    test('alternating on the beat darkens odd lamps, then even ones', () async {
      final service = ArtNetService();
      final beats = StreamController<DateTime>.broadcast();
      final controller = DimmerDropoutController(service, beatEvents: () => beats.stream, beatsListening: () => true);
      addTearDown(() {
        controller.dispose();
        beats.close();
      });
      controller.refreshScope(pars, const [universe]);
      controller.update(
        const DropoutSettings(enabled: true, onBeat: true, lengthMs: 200, pattern: DropoutPattern.alternate),
      );
      Set<int> dark() => service.darkChannels!(universe);

      beats.add(DateTime.now());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(dark(), {0, 2});

      beats.add(DateTime.now());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(dark(), {1, 3});

      beats.add(DateTime.now());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(dark(), {0, 2});
    });

    test('all at once still cuts every lamp', () async {
      final service = ArtNetService();
      final beats = StreamController<DateTime>.broadcast();
      final controller = DimmerDropoutController(service, beatEvents: () => beats.stream, beatsListening: () => true);
      addTearDown(() {
        controller.dispose();
        beats.close();
      });
      controller.refreshScope(pars, const [universe]);
      controller.update(const DropoutSettings(enabled: true, onBeat: true, lengthMs: 200));
      beats.add(DateTime.now());
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(service.darkChannels!(universe), {0, 1, 2, 3});
    });

    test('random on the beat cuts the share of the chosen lamps only', () async {
      final service = ArtNetService();
      final beats = StreamController<DateTime>.broadcast();
      final controller = DimmerDropoutController(
        service,
        random: Random(2),
        beatEvents: () => beats.stream,
        beatsListening: () => true,
      );
      addTearDown(() {
        controller.dispose();
        beats.close();
      });
      controller.refreshScope(pars, const [universe]);
      controller.update(
        const DropoutSettings(
          enabled: true,
          onBeat: true,
          lengthMs: 200,
          pattern: DropoutPattern.random,
          randomShare: 0.5,
          fixtureIds: {'p0', 'p1', 'p2', 'p3'},
        ),
      );
      for (var i = 0; i < 5; i++) {
        beats.add(DateTime.now());
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final dark = service.darkChannels!(universe);
        expect(dark.length, 2);
        expect(dark.difference({0, 1, 2, 3}), isEmpty);
      }
    });
  });
}
