import 'dart:math';
import 'dart:typed_data';

import 'package:dmx_controller/core/artnet/artnet_service.dart';
import 'package:dmx_controller/core/playback/dimmer_dropout.dart';
import 'package:dmx_controller/models/universe_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('applyDropout', () {
    test('returns the frame itself when nothing is cut', () {
      final frame = Uint8List.fromList([1, 2, 3]);
      expect(identical(applyDropout(frame, const {}), frame), isTrue);
    });

    test('zeroes only the named channels and leaves the buffer alone', () {
      final frame = Uint8List.fromList([10, 20, 30, 40]);
      final out = applyDropout(frame, {1, 3, 99});
      expect(out, [10, 0, 30, 0]);
      expect(frame, [10, 20, 30, 40]);
    });
  });

  group('DropoutSettings json', () {
    test('survives a round trip', () {
      const settings = DropoutSettings(
        enabled: true,
        targetLayerIds: {'layer-2'},
        fixtureIds: {'f1', 'f2'},
        lengthMs: 80,
        intervalMs: 6000,
        jitter: 0.25,
      );
      final back = DropoutSettings.fromJson(settings.toJson());
      expect(back.enabled, isTrue);
      expect(back.targetLayerIds, {'layer-2'});
      expect(back.fixtureIds, {'f1', 'f2'});
      expect(back.lengthMs, 80);
      expect(back.intervalMs, 6000);
      expect(back.jitter, 0.25);
    });

    test('an old project without it, or with nonsense, gets safe defaults', () {
      expect(DropoutSettings.fromJson(null).enabled, isFalse);
      final odd = DropoutSettings.fromJson({'lengthMs': 99999, 'intervalMs': 1, 'jitter': 7});
      expect(odd.lengthMs, DropoutSettings.maxLengthMs);
      expect(odd.intervalMs, DropoutSettings.minIntervalMs);
      expect(odd.jitter, 1.0);
    });
  });

  group('dropoutGap', () {
    test('without jitter it is the interval minus the dark', () {
      const settings = DropoutSettings(intervalMs: 4000, lengthMs: 100, jitter: 0);
      expect(dropoutGap(settings, Random(1)), const Duration(milliseconds: 3900));
    });

    test('with jitter it stays within 0..2x of the lit time, never under a frame or two', () {
      const settings = DropoutSettings(intervalMs: 1000, lengthMs: 500, jitter: 1);
      final random = Random(7);
      for (var i = 0; i < 200; i++) {
        final gap = dropoutGap(settings, random).inMilliseconds;
        expect(gap, inInclusiveRange(60, 1000));
      }
    });
  });

  group('ArtNetService.channelsOwnedBy', () {
    const universe = UniverseConfig(id: 'u1', name: 'U1', universe: 0);

    test('only channels a targeted layer currently owns can be cut', () {
      final service = ArtNetService();
      service.claimLayer('a');
      service.setLayerChannel(universe, 0, 200, 'a');
      service.claimLayer('b');
      service.setLayerChannel(universe, 1, 200, 'b');
      // b started later, so it takes channel 0 from a.
      service.setLayerChannel(universe, 0, 50, 'b');

      expect(service.channelsOwnedBy(universe, {'a'}, {0, 1}), isEmpty);
      expect(service.channelsOwnedBy(universe, {'b'}, {0, 1}), {0, 1});
      expect(service.channelsOwnedBy(universe, {'b'}, {1}), {1});
    });

    test('a universe nothing wrote to has nothing to cut', () {
      expect(ArtNetService().channelsOwnedBy(universe, {'a'}, {0}), isEmpty);
    });
  });
}
