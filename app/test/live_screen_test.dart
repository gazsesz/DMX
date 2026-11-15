import 'package:dmx_controller/features/live/live_screen.dart';
import 'package:dmx_controller/models/live_grid.dart';
import 'package:dmx_controller/state/live_providers.dart';
import 'package:dmx_controller/state/playback_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('tablet Grid: tap a clip queues it as NEXT, GO starts it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: LiveScreen())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('live-go')), findsOneWidget);
    expect(find.text('Warm wash'), findsOneWidget);

    container.read(livePrefsProvider.notifier).setQuantize(LiveQuantize.now);
    await tester.tap(find.text('Warm wash'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(container.read(liveStatusProvider).queued['colors-pars'], 0);
    expect(find.text('NEXT'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('live-go')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(liveStatusProvider).running['colors-pars'], 0);
    expect(find.text('NEXT'), findsNothing);

    // The dock's Stop (and the remote's /stop) ends the Grid too.
    stopPlayback(container.read);
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(liveStatusProvider).anyRunning, isFalse);

    // The help explains the two-step pick + GO.
    await tester.tap(find.byKey(const ValueKey('live-help')));
    await tester.pumpAndSettle();
    expect(find.text('How the Grid works'), findsWidgets);
    await tester.tap(find.text('Done'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('a pad can hold a Bank / Chase / Scene; lanes can be added', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: LiveScreen())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    await tester.longPress(find.text('Warm wash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bank / Chase / Scene'));
    await tester.pumpAndSettle();
    // Nothing picked yet: Save stays off.
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('live-clip-save'))).onPressed, isNull);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Bank 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('live-clip-save')));
    await tester.pumpAndSettle();
    final clip = container.read(liveGridProvider).clipAt('colors-pars', 0)!;
    expect(clip.show?.kind, LiveShowKind.bank);
    expect(clip.name, 'Bank 1');
    expect(clip.colors, isNull);
    expect(find.text('Bank 1'), findsOneWidget);

    final before = container.read(liveGridProvider).lanes.length;
    await tester.tap(find.byKey(const ValueKey('live-add-lane')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('live-add-lane-show')));
    await tester.pumpAndSettle();
    final lanes = container.read(liveGridProvider).lanes;
    expect(lanes.length, before + 1);
    expect(lanes.last.kind, LiveLaneKind.show);
    expect(lanes.last.id, 'show-2');

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('phone Grid shows lane chips and a GO button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: LiveScreen())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(ChoiceChip), findsWidgets);
    expect(find.text('GO'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 300));
  });

  // Tab S6 Lite (landscape / portrait) and P20 Pro landscape lay out cleanly.
  for (final size in const [Size(1333, 800), Size(800, 1333), Size(746, 360)]) {
    testWidgets('lays out without overflow at ${size.width}x${size.height}', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: LiveScreen())),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('GO'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.pump(const Duration(milliseconds: 300));
    });
  }
}
