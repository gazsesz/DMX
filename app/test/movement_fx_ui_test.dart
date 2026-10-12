import 'package:dmx_controller/core/theme/app_theme.dart';
import 'package:dmx_controller/features/banks/banks_screen.dart';
import 'package:dmx_controller/models/bank.dart';
import 'package:dmx_controller/models/movement_fx.dart';
import 'package:dmx_controller/state/bank_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          (call) async => null,
        );
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> open(WidgetTester tester, List<Bank> banks) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(banksProvider.notifier).loadAll(banks);
    container.read(selectedBankIdProvider.notifier).state = banks.first.id;
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildAppTheme(), home: const BanksScreen()),
      ),
    );
    await _settle(tester);
    return container;
  }

  testWidgets('a Movement FX bank shows its editor instead of the slot grid', (
    tester,
  ) async {
    await open(tester, [
      const Bank(
        id: 'fx',
        name: 'Swim',
        sceneSlots: [],
        fx: MovementFx(shape: MovementShape.swim),
      ),
    ]);
    expect(find.text('Lock to the beat'), findsOneWidget);
    expect(find.text('Edit slots'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking a shape and locking to the beat edits the bank', (
    tester,
  ) async {
    final container = await open(tester, [
      const Bank(id: 'fx', name: 'Move', sceneSlots: [], fx: MovementFx()),
    ]);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Float'));
    await _settle(tester);
    expect(container.read(banksProvider).first.fx!.shape, MovementShape.float);
    await tester.tap(find.text('Lock to the beat'));
    await _settle(tester);
    expect(container.read(banksProvider).first.fx!.beatLocked, isTrue);
    await tester.tap(find.widgetWithText(ChoiceChip, '8 beats'));
    await _settle(tester);
    expect(container.read(banksProvider).first.fx!.beats, 8);
  });

  testWidgets('the Movement FX button makes a bank from a preset', (
    tester,
  ) async {
    final container = await open(tester, [
      const Bank(id: 'b', name: 'Bank 1', sceneSlots: [null]),
    ]);
    await tester.tap(find.text('Movement FX'));
    await _settle(tester);
    await tester.tap(find.text('Light rider'));
    await _settle(tester);
    final banks = container.read(banksProvider);
    expect(banks.length, 2);
    expect(banks.last.fx!.shape, MovementShape.lightRider);
    expect(banks.last.sceneSlots, isEmpty);
    expect(container.read(selectedBankIdProvider), banks.last.id);
  });

  testWidgets('a look bank is picked, timed and cleared in the editor', (
    tester,
  ) async {
    final container = await open(tester, [
      const Bank(id: 'fx', name: 'Move', sceneSlots: [], fx: MovementFx()),
      const Bank(id: 'cols', name: 'Colours', sceneSlots: ['s1']),
    ]);
    await tester.scrollUntilVisible(
      find.text('Pick bank'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Pick bank'));
    await _settle(tester);
    await tester.tap(find.text('Colours').last);
    await _settle(tester);
    expect(container.read(banksProvider).first.fx!.lookBankId, 'cols');
    await tester.tap(find.text('Own timing'));
    await _settle(tester);
    expect(container.read(banksProvider).first.fx!.lookOwnTiming, isTrue);
    await tester.tap(find.byTooltip('No look'));
    await _settle(tester);
    expect(container.read(banksProvider).first.fx!.lookBankId, isNull);
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
