import 'package:dmx_controller/core/theme/app_theme.dart';
import 'package:dmx_controller/features/banks/banks_screen.dart';
import 'package:dmx_controller/models/artnet_settings.dart';
import 'package:dmx_controller/models/bank.dart';
import 'package:dmx_controller/models/layer.dart';
import 'package:dmx_controller/models/scene.dart';
import 'package:dmx_controller/state/artnet_providers.dart';
import 'package:dmx_controller/state/bank_providers.dart';
import 'package:dmx_controller/state/playback_providers.dart';
import 'package:dmx_controller/state/scene_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A bank step can carry its own Hold/Fade ([Bank.slotTimings]), which wins
/// over the bank's own timing and the dock's, and can be reset.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async => null,
    );
    SharedPreferences.setMockInitialValues({});
  });

  group('model', () {
    test('step timings survive a save and load, and old banks have none', () {
      const bank = Bank(
        id: 'b',
        name: 'B',
        sceneSlots: ['s1', 's2', null],
        slotTimings: [null, SlotTiming(holdMs: 500, fadeMs: 2000)],
      );
      final back = Bank.fromJson(bank.toJson());
      expect(back.timingAt(0), isNull);
      expect(back.timingAt(1), const SlotTiming(holdMs: 500, fadeMs: 2000));
      expect(back.timingAt(2), isNull);
      final old = Bank.fromJson({'id': 'o', 'name': 'O', 'sceneSlots': ['s1']});
      expect(old.hasStepTimings, isFalse);
      expect(old.toJson().containsKey('slotTimings'), isFalse);
    });

    test('set, move with the step, reset, and drop when the slot is cleared', () {
      final notifier = BanksNotifier();
      final id = notifier.state.first.id;
      notifier
        ..setSlot(id, 0, 's1')
        ..setSlot(id, 1, 's2')
        ..setSlotTiming(id, 0, const SlotTiming(holdMs: 100, fadeMs: 50));
      expect(notifier.state.first.timingAt(0), const SlotTiming(holdMs: 100, fadeMs: 50));

      notifier.moveSlot(id, 0, 1);
      expect(notifier.state.first.sceneSlots.take(2), ['s2', 's1']);
      expect(notifier.state.first.timingAt(0), isNull);
      expect(notifier.state.first.timingAt(1), const SlotTiming(holdMs: 100, fadeMs: 50));

      notifier.setSlot(id, 1, 's3');
      expect(notifier.state.first.timingAt(1), isNotNull, reason: 'swapping the scene keeps the step timing');

      notifier.setSlotTiming(id, 1, null);
      expect(notifier.state.first.hasStepTimings, isFalse);

      notifier
        ..setSlotTiming(id, 1, const SlotTiming(holdMs: 100, fadeMs: 50))
        ..setSlot(id, 1, null);
      expect(notifier.state.first.hasStepTimings, isFalse, reason: 'an empty slot is not a step');

      notifier
        ..setSlot(id, 0, 's1')
        ..setSlotTiming(id, 0, const SlotTiming(holdMs: 100, fadeMs: 50));
      final copy = notifier.duplicate(id)!;
      expect(copy.timingAt(0), isNotNull);
      notifier.clearSlotTimings(id);
      expect(notifier.state.first.hasStepTimings, isFalse);
    });
  });

  testWidgets('the slot menu sets a step\'s own timing, and Reset puts it back', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(scenesProvider.notifier).upsert(const Scene(id: 's1', name: 'One', fixtureValues: {}));
    final bankId = container.read(banksProvider).first.id;
    container.read(banksProvider.notifier)
      ..setSlot(bankId, 0, 's1')
      ..setTiming(bankId, ownTiming: true, holdMs: 2000, fadeMs: 400);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildAppTheme(), home: const BanksScreen()),
    ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.edit).first);
    await _settle(tester);
    await tester.tap(find.text('Step timing…'));
    await _settle(tester);
    expect(find.textContaining('Follows the bank: Hold 2.00s · Fade 0.40s'), findsOneWidget);

    await tester.tap(find.text('Own timing for this step'));
    await _settle(tester);
    // Starts from what the step was already playing at.
    expect(container.read(banksProvider).first.timingAt(0), const SlotTiming(holdMs: 2000, fadeMs: 400));

    await tester.tap(find.textContaining('Reset'));
    await _settle(tester);
    expect(container.read(banksProvider).first.timingAt(0), isNull);
  });

  testWidgets('a step with its own short hold moves on while the bank\'s long hold waits', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(artNetServiceProvider).connect(const ArtNetSettings(demoMode: true)));
    container.read(scenesProvider.notifier)
      ..upsert(const Scene(id: 's1', name: 'One', fixtureValues: {}))
      ..upsert(const Scene(id: 's2', name: 'Two', fixtureValues: {}))
      ..upsert(const Scene(id: 's3', name: 'Three', fixtureValues: {}));
    final bankId = container.read(banksProvider).first.id;
    container.read(banksProvider.notifier)
      ..setSlot(bankId, 0, 's1')
      ..setSlot(bankId, 1, 's2')
      ..setSlot(bankId, 2, 's3')
      // The bank holds each step for 5 s; step 1 only 60 ms.
      ..setTiming(bankId, ownTiming: true, holdMs: 5000, fadeMs: 0)
      ..setSlotTiming(bankId, 0, const SlotTiming(holdMs: 60, fadeMs: 0));

    final error = runBankOnLayer(container.read, bank: container.read(banksProvider).first, layerId: layer1Id);
    expect(error, isNull);
    // The player times holds on the wall clock but waits on test timers, so
    // let real time pass and pump between looks.
    final seen = <int?>{};
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 50));
      seen.add(container.read(layerStepProvider(layer1Id)));
    }
    expect(seen, {0, 1}, reason: 'step 1 left after 60 ms, step 2 holds the bank\'s 5 s');

    container.read(chasePlayerProvider(layer1Id)).stop();
    await tester.pump(const Duration(milliseconds: 100));
  });
}

/// The Banks screen animates all the time (the beat meter), so it never
/// "settles"; give dialogs and sheets a fixed while to open and close.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
