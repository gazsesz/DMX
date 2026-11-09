import 'package:dmx_controller/app.dart';
import 'package:dmx_controller/features/settings/settings_screen.dart';
import 'package:dmx_controller/features/shell/app_shell.dart';
import 'package:dmx_controller/state/locale_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('device language: Hungarian stays Hungarian, anything else is English', () {
    expect(resolveAppLocale(const [Locale('hu', 'HU')]), const Locale('hu'));
    expect(resolveAppLocale(const [Locale('de'), Locale('hu')]), const Locale('hu'));
    expect(resolveAppLocale(const [Locale('de')]), const Locale('en'));
    expect(resolveAppLocale(null), const Locale('en'));
    expect(AppLanguage.fromName('hu'), AppLanguage.hu);
    expect(AppLanguage.fromName('xx'), AppLanguage.system);
    expect(AppLanguage.fromName(null), AppLanguage.system);
  });

  testWidgets('switching the language relabels the app at once and is saved', (tester) async {
    final container = ProviderContainer(
      overrides: [appLanguageProvider.overrideWith((ref) => AppLanguageNotifier(AppLanguage.en))],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const DmxControllerApp(home: AppShell())),
    );
    expect(find.text('Setup'), findsWidgets);
    expect(find.text('Beállítás'), findsNothing);

    container.read(appLanguageProvider.notifier).set(AppLanguage.hu);
    await tester.pump();
    expect(find.text('Beállítás'), findsWidgets);
    expect(find.text('Setup'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(prefAppLanguage), 'hu');
  });

  // Hungarian runs longer than English — the Setup screen (where the
  // switch lives) must still lay out on the phone without overflowing.
  for (final size in const [Size(360, 740), Size(1340, 800)]) {
    testWidgets('Setup lays out in Hungarian at ${size.width.toInt()} px wide', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [appLanguageProvider.overrideWith((ref) => AppLanguageNotifier(AppLanguage.hu))],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const DmxControllerApp(home: SettingsScreen())),
      );
      await tester.pump();
      expect(find.text('Beállítások'), findsOneWidget);
      expect(find.text('Magyar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
