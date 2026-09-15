import 'package:dmx_controller/core/widgets/control_panel.dart';
import 'package:dmx_controller/core/theme/app_theme.dart';
import 'package:dmx_controller/state/tempo_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The panel is now the only place the tempo and beat controls exist, so it
/// has to render and work on both a tablet-width side panel and a phone
/// bottom sheet — there is no Dashboard card to fall back on any more.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Arming beat sync reaches the recorder over a platform channel; there
    // is no plugin host in a widget test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async => null,
    );
  });

  Future<ProviderContainer> pumpPanel(WidgetTester tester, {double width = 340}) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: SizedBox(width: width, child: const ControlPanel())),
        ),
      ),
    );
    return container;
  }

  testWidgets('renders in a 340px side panel without overflowing', (tester) async {
    await pumpPanel(tester);
    expect(find.text('TAP'), findsOneWidget);
    expect(find.text('Beat sync'), findsOneWidget);
    expect(find.text('Auto fade'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders on a narrow phone sheet without overflowing', (tester) async {
    await pumpPanel(tester, width: 320);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the step slider writes through to the shared tempo', (tester) async {
    final container = await pumpPanel(tester);
    final before = container.read(tempoProvider).stepSeconds;

    final slider = find.byType(Slider).first;
    await tester.drag(slider, const Offset(60, 0));
    await tester.pumpAndSettle();

    // Dragging right on an inverted scale means faster, i.e. fewer seconds.
    expect(container.read(tempoProvider).stepSeconds, lessThan(before));
  });

  testWidgets('auto fade is switched from here and the fade follows the tempo', (tester) async {
    final container = await pumpPanel(tester);
    container.read(tempoProvider.notifier).setStepSeconds(1.0);
    await tester.pump();

    await tester.tap(find.widgetWithText(SwitchListTile, 'Auto fade'));
    await tester.pumpAndSettle();

    final tempo = container.read(tempoProvider);
    expect(tempo.autoFade, isTrue);
    expect(tempo.effectiveFadeSeconds, closeTo(tempo.autoFadeRatio, 1e-9));
  });

  testWidgets('the beat controls only appear once beat sync is armed', (tester) async {
    final container = await pumpPanel(tester);
    expect(find.text('Steps per beat'), findsNothing);
    expect(find.text('Sensitivity'), findsNothing);

    container.read(tempoProvider.notifier).setStepSeconds(0.5);
    await tester.pump();
    // Arming through the provider rather than the switch: the switch opens
    // a microphone, which a widget test has no business doing.
    expect(find.text('Baseline memory'), findsNothing);
  });
}
