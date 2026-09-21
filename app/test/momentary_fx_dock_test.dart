import 'package:dmx_controller/core/widgets/control_dock.dart';
import 'package:dmx_controller/models/control_dock_prefs.dart';
import 'package:dmx_controller/state/artnet_providers.dart';
import 'package:dmx_controller/state/momentary_fx_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The whole promise of these three buttons is that they end when you let go.
/// A held effect that outlives the finger holding it is a rig left strobing
/// with nothing on screen saying why, so that's what these pin down.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async => null,
    );
  });

  Future<ProviderContainer> pumpDock(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(child: SizedBox.expand()),
                ControlDock(position: ControlDockPosition.bottom),
              ],
            ),
          ),
        ),
      ),
    );
    return container;
  }

  testWidgets('the three momentary buttons are on the strip', (tester) async {
    await pumpDock(tester);
    expect(find.text('Strobe'), findsOneWidget);
    expect(find.text('Blinder'), findsOneWidget);
    expect(find.text('Freeze'), findsOneWidget);
  });

  testWidgets('holding a button engages the effect, letting go drops it', (tester) async {
    final container = await pumpDock(tester);
    final service = container.read(artNetServiceProvider);

    final gesture = await tester.startGesture(tester.getCenter(find.text('Freeze')));
    await tester.pump();
    expect(container.read(momentaryFxProvider), {MomentaryFx.freeze});
    expect(service.outputOverride, isNotNull, reason: 'the layer is on the output');

    await gesture.up();
    await tester.pump();
    expect(container.read(momentaryFxProvider), isEmpty);
    expect(
      service.outputOverride,
      isNull,
      reason: 'clearing the layer is the restore — the buffers never changed',
    );
  });

  testWidgets('a finger that slides off the button still holds it', (tester) async {
    // A tap gesture would have given up at the touch slop and dropped the
    // effect mid-hold, which is why these are raw pointer listeners.
    final container = await pumpDock(tester);
    final gesture = await tester.startGesture(tester.getCenter(find.text('Blinder')));
    await gesture.moveBy(const Offset(40, 40));
    await tester.pump();
    expect(container.read(momentaryFxProvider), {MomentaryFx.blinder});

    await gesture.up();
    await tester.pump();
    expect(container.read(momentaryFxProvider), isEmpty);
  });

  testWidgets('two held at once compose, and each releases on its own', (tester) async {
    final container = await pumpDock(tester);
    final strobe = await tester.startGesture(tester.getCenter(find.text('Strobe')));
    final blinder = await tester.startGesture(tester.getCenter(find.text('Blinder')));
    await tester.pump(const Duration(milliseconds: 120));
    expect(container.read(momentaryFxProvider), {MomentaryFx.strobe, MomentaryFx.blinder});

    await blinder.up();
    await tester.pump();
    expect(container.read(momentaryFxProvider), {MomentaryFx.strobe});

    await strobe.up();
    await tester.pump();
    expect(
      container.read(momentaryFxProvider),
      isEmpty,
      reason: 'and the strobe timer goes with it, or this test would not end',
    );
  });

  testWidgets('releaseAll ends everything — what Blackout leans on', (tester) async {
    final container = await pumpDock(tester);
    final freeze = await tester.startGesture(tester.getCenter(find.text('Freeze')));
    final strobe = await tester.startGesture(tester.getCenter(find.text('Strobe')));
    await tester.pump();

    container.read(momentaryFxProvider.notifier).releaseAll();
    await tester.pump();
    expect(container.read(momentaryFxProvider), isEmpty);
    expect(container.read(artNetServiceProvider).outputOverride, isNull);

    await freeze.up();
    await strobe.up();
    await tester.pump();
  });

  testWidgets('a button taken off screen mid-hold ends its effect', (tester) async {
    // The strip gives controls up as the screen narrows, and a rotation can
    // do that with a finger still down.
    final container = await pumpDock(tester);
    final gesture = await tester.startGesture(tester.getCenter(find.text('Strobe')));
    await tester.pump();
    expect(container.read(momentaryFxProvider), {MomentaryFx.strobe});

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SizedBox.expand())),
      ),
    );
    await tester.pump();
    expect(container.read(momentaryFxProvider), isEmpty);
    await gesture.up();
  });
}
