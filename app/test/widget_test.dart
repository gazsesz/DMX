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
}
