import 'package:dmx_controller/core/theme/app_theme.dart';
import 'package:dmx_controller/features/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Pumps AppShell directly rather than DmxControllerApp: the app now opens
  // on the splash screen, which loads the last project and connects to the
  // node before handing over — none of which a widget test can complete.
  testWidgets('App shell shows the Dashboard tab by default', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: buildAppTheme(), home: const AppShell()),
      ),
    );

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('QUICK TRIGGERS'), findsOneWidget);
  });

  // Scenes folded into Banks: a slot picks, creates and edits scenes in
  // place, so the library is a second-level screen behind the Banks app bar
  // rather than a tab of its own. If a 'Scene' destination comes back, the
  // two ways of reaching the same list have drifted apart again.
  testWidgets('the shell has no Scene tab', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: buildAppTheme(), home: const AppShell()),
      ),
    );

    expect(find.text('Bank'), findsWidgets);
    expect(find.text('Scene'), findsNothing);
  });
}
