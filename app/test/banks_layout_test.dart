import 'package:dmx_controller/core/theme/app_theme.dart';
import 'package:dmx_controller/features/banks/banks_screen.dart';
import 'package:dmx_controller/models/bank.dart';
import 'package:dmx_controller/models/scene.dart';
import 'package:dmx_controller/state/bank_providers.dart';
import 'package:dmx_controller/state/scene_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Banks screen on a small screen with a big show: the slots must stay
/// reachable however many banks there are, and picking a slot's scene
/// mustn't depend on hitting a tiny corner icon.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async => null,
    );
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> open(WidgetTester tester, {required int bankCount, Size size = const Size(800, 600)}) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(scenesProvider.notifier).loadAll([
      const Scene(id: 's1', name: 'Purple', fixtureValues: {}),
      const Scene(id: 's2', name: 'Strobe', fixtureValues: {}),
    ]);
    container.read(banksProvider.notifier).loadAll([
      for (var b = 0; b < bankCount; b++) Bank(id: 'b$b', name: 'Bank ${b + 1}', sceneSlots: const ['s1', null, null, null]),
    ]);
    container.read(selectedBankIdProvider.notifier).state = 'b0';
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildAppTheme(), home: const BanksScreen()),
    ));
    await _settle(tester);
    return container;
  }

  testWidgets('with 40 banks on a small screen the slots can still be scrolled to and used', (tester) async {
    await open(tester, bankCount: 40);
    final slot = find.text('Purple');
    await tester.scrollUntilVisible(slot, 120, scrollable: find.byType(Scrollable).first);
    await tester.tap(slot, warnIfMissed: true);
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Edit slots: tapping anywhere on a slot opens its menu', (tester) async {
    final container = await open(tester, bankCount: 3, size: const Size(1200, 900));
    await tester.tap(find.text('Edit slots'));
    await _settle(tester);
    await tester.tap(find.text('Purple'));
    await _settle(tester);
    expect(find.text('Slot 1'), findsOneWidget);
    await tester.tap(find.text('Strobe').last);
    await _settle(tester);
    expect(container.read(banksProvider).first.sceneSlots.first, 's2');
  });

  testWidgets('All banks finds a bank by name and selects it', (tester) async {
    final container = await open(tester, bankCount: 40, size: const Size(1200, 900));
    await tester.tap(find.text('All banks (40)'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).last, '37');
    await _settle(tester);
    await tester.tap(find.text('Bank 37').last);
    await _settle(tester);
    expect(container.read(selectedBankIdProvider), 'b36');
  });
}

/// The Banks screen animates all the time (the beat meter), so it never
/// "settles"; give dialogs and sheets a fixed while to open and close.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
