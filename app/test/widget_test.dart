import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dmx_controller/app.dart';

void main() {
  testWidgets('App shell shows the Dashboard tab by default', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: DmxControllerApp()));

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('QUICK TRIGGERS'), findsOneWidget);
  });
}
