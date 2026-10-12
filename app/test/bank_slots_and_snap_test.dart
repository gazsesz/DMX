import 'package:dmx_controller/core/widgets/pan_tilt_pad.dart';
import 'package:dmx_controller/models/bank.dart';
import 'package:dmx_controller/models/pan_tilt.dart';
import 'package:dmx_controller/state/bank_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Degrees from the nearest multiple of [step].
double _offGrid(double deg, double step) {
  final r = deg % step;
  return r < step - r ? r : step - r;
}

void main() {
  group('removeEmptySlot', () {
    test('drops an empty slot in the middle and moves the rest up', () {
      final notifier = BanksNotifier()
        ..loadAll([
          const Bank(id: 'b', name: 'B', sceneSlots: ['a', null, 'c']),
        ]);
      expect(notifier.removeEmptySlot('b', 1), isTrue);
      expect(notifier.state.single.sceneSlots, ['a', 'c']);
    });

    test('never removes a slot holding a scene, or the last slot', () {
      final notifier = BanksNotifier()
        ..loadAll([
          const Bank(id: 'b', name: 'B', sceneSlots: ['a', null]),
          const Bank(id: 'c', name: 'C', sceneSlots: [null]),
        ]);
      expect(notifier.removeEmptySlot('b', 0), isFalse);
      expect(notifier.removeEmptySlot('c', 0), isFalse);
      expect(notifier.state.first.sceneSlots, ['a', null]);
    });
  });

  group('duplicate', () {
    test('shares the scenes without a map', () {
      final notifier = BanksNotifier()
        ..loadAll([
          const Bank(id: 'b', name: 'B', sceneSlots: ['a', null, 'a']),
        ]);
      expect(notifier.duplicate('b')!.sceneSlots, ['a', null, 'a']);
    });

    test('points at the mapped clones, one per scene', () {
      final notifier = BanksNotifier()
        ..loadAll([
          const Bank(id: 'b', name: 'B', sceneSlots: ['a', null, 'a', 'x']),
        ]);
      final copy = notifier.duplicate('b', sceneMap: {'a': 'a2', 'x': 'x2'})!;
      expect(copy.sceneSlots, ['a2', null, 'a2', 'x2']);
      expect(notifier.state.first.sceneSlots, ['a', null, 'a', 'x']);
    });
  });

  group('PanTiltPad snap', () {
    Future<PanTilt> dragTo(WidgetTester tester, PadSnap snap, Offset fractionOfPad) async {
      PanTilt? last;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 400,
              child: PanTiltPad(
                value: const PanTilt(0, 0),
                panRangeDeg: 540,
                tiltRangeDeg: 270,
                snap: snap,
                onChanged: (v) => last = v,
              ),
            ),
          ),
        ),
      );
      final box = tester.getRect(find.byType(PanTiltPad));
      final at = box.topLeft + Offset(box.width * fractionOfPad.dx, box.height * fractionOfPad.dy);
      final gesture = await tester.startGesture(at);
      await gesture.up();
      await tester.pump();
      return last!;
    }


    testWidgets('whole snaps to the 45° lines', (tester) async {
      final v = await dragTo(tester, PadSnap.whole, const Offset(0.30, 0.5));
      final panDeg = v.pan / PanTilt.max * 540;
      expect(_offGrid(panDeg, 45), closeTo(0, 0.05));
    });

    testWidgets('quarter snaps to 11.25° steps', (tester) async {
      final v = await dragTo(tester, PadSnap.quarter, const Offset(0.3, 0.5));
      final panDeg = v.pan / PanTilt.max * 540;
      expect(_offGrid(panDeg, 11.25), closeTo(0, 0.05));
    });

    testWidgets('free does not snap', (tester) async {
      final v = await dragTo(tester, PadSnap.off, const Offset(0.3123, 0.5));
      final panDeg = v.pan / PanTilt.max * 540;
      expect(_offGrid(panDeg, 11.25), greaterThan(0.05));
    });
  });
}
