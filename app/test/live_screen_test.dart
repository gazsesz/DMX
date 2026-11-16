import 'package:dmx_controller/features/live/live_screen.dart';
import 'package:dmx_controller/models/channel_capability.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/state/fixture_providers.dart';
import 'package:dmx_controller/models/live_grid.dart';
import 'package:dmx_controller/state/live_providers.dart';
import 'package:dmx_controller/state/playback_providers.dart';
import 'package:dmx_controller/models/smart_program.dart';
import 'package:dmx_controller/state/smart_program_providers.dart';
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

    // The Beam editor opens fine with no fixtures patched.
    await tester.longPress(find.text('Strobe'));
    await tester.pumpAndSettle();
    expect(find.text('Gobo'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final before = container.read(liveGridProvider).lanes.length;
    await tester.tap(find.byKey(const ValueKey('live-add-lane')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('live-add-lane-show')));
    await tester.pumpAndSettle();
    final lanes = container.read(liveGridProvider).lanes;
    expect(lanes.length, before + 1);
    expect(lanes.last.kind, LiveLaneKind.show);
    expect(lanes.last.id, 'show-2');

    // Rename it and move it one place left from the lane settings.
    await tester.tap(find.text('Show').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('live-lane-name')), 'Banks');
    await tester.tap(find.byKey(const ValueKey('live-lane-left')));
    await tester.pumpAndSettle();
    final moved = container.read(liveGridProvider).lanes;
    expect(moved[moved.length - 2].id, 'show-2');
    expect(moved[moved.length - 2].name, 'Banks');
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('live-lane-right'))).onPressed, isNotNull);
    Navigator.of(tester.element(find.byKey(const ValueKey('live-lane-name')))).pop();
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('Moves editor shows the path preview, like the bank editor', (tester) async {
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
    await tester.longPress(find.text('Circle'));
    // The preview animates for ever: pump, don't settle.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('live-moves-preview')), findsOneWidget);

    // The base pan/tilt can be moved off the centre and back.
    await tester.ensureVisible(find.byKey(const ValueKey('live-moves-centre')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(tester.getTopLeft(find.byKey(const ValueKey('live-moves-centre'))) + const Offset(30, 30));
    await tester.pump(const Duration(milliseconds: 100));
    // Try on heads, then save from the top row.
    await tester.ensureVisible(find.byKey(const ValueKey('live-moves-try')));
    await tester.tap(find.byKey(const ValueKey('live-moves-try')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.byKey(const ValueKey('live-clip-save-top')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('live-clip-save-top')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final moved = container.read(liveGridProvider).clipAt('moves', 0)!.moves!.center;
    expect(moved.pan, lessThan(32768));
    expect(moved.tilt, lessThan(32768));

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('Beam editor: a prism whose "in" is a span can be set', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    const head = FixtureProfile(
      id: 'head',
      name: 'Head',
      category: FixtureCategory.movingHead,
      channels: [
        FixtureChannel(offset: 0, function: ChannelFunction.pan),
        FixtureChannel(offset: 1, function: ChannelFunction.tilt),
        FixtureChannel(
          offset: 2,
          function: ChannelFunction.prism,
          capabilities: [
            ChannelCapability(min: 0, max: 7, label: 'No prism', kind: CapabilityKind.off),
            ChannelCapability(min: 8, max: 255, label: 'Prism rotation', kind: CapabilityKind.range),
          ],
        ),
      ],
    );
    container.read(patchedFixturesProvider.notifier).loadAll([
      const PatchedFixture(id: 'h1', label: 'h1', profile: head, universeId: 'u', startChannel: 0),
    ]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: LiveScreen())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.longPress(find.text('Strobe'));
    await tester.pumpAndSettle();
    expect(find.text('Prism'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Prism rotation'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('live-clip-save')));
    await tester.pumpAndSettle();
    expect(container.read(liveGridProvider).clipAt('beam', 2)!.beam!.prism, 8);

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('Mixer: strips with Amount faders; the running mix saves as a scene', (tester) async {
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

    await tester.tap(find.text('Mixer'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-amount-level')), findsOneWidget);
    expect(find.text('Idle'), findsWidgets);

    // Nothing running: nothing to save.
    await tester.tap(find.byKey(const ValueKey('live-mix-save')));
    await tester.pump();
    expect(find.text('Nothing is running to save.'), findsOneWidget);

    // Drag the Level fader to the left end.
    final slider = find.byKey(const ValueKey('live-amount-level'));
    await tester.drag(slider, const Offset(-400, 0));
    await tester.pump();
    expect(container.read(liveGridProvider).lane('level')!.amount, lessThan(0.05));

    // Run two clips, then save the mix as a new row.
    final engine = container.read(liveEngineProvider);
    engine.select('colors-pars', 0, mode: LivePadMode.launchDirectly, quantize: LiveQuantize.now);
    engine.select('moves', 1, mode: LivePadMode.launchDirectly, quantize: LiveQuantize.now);
    // Level ran, then was stopped: the saved row still gets its clip.
    engine.select('level', 2, mode: LivePadMode.launchDirectly, quantize: LiveQuantize.now);
    await tester.pump(const Duration(milliseconds: 100));
    engine.stopLane('level');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('NOW · '), findsNWidgets(2));
    final rowsBefore = container.read(liveGridProvider).rows.length;
    await tester.tap(find.byKey(const ValueKey('live-mix-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final grid = container.read(liveGridProvider);
    expect(grid.rows.length, rowsBefore + 1);
    expect(grid.clipAt('colors-pars', rowsBefore)?.name, grid.clipAt('colors-pars', 0)?.name);
    expect(grid.clipAt('moves', rowsBefore)?.name, grid.clipAt('moves', 1)?.name);
    expect(grid.clipAt('level', rowsBefore)?.name, grid.clipAt('level', 2)?.name);
    expect(grid.clipAt('level', rowsBefore), isNotNull);
    expect(find.textContaining("Level wasn't running"), findsOneWidget);
    expect(grid.clipAt('beam', rowsBefore), isNull);

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('row menu: copy and delete; rows a Smart Program plays wear a badge', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    final first = container.read(liveGridProvider);
    container.read(smartProgramsProvider.notifier).loadAll([
      SmartProgram(id: 'p', name: 'Club', gridRows: {SmartProgramZone.base: first.rowIds[1]}),
    ]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: LiveScreen())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('live-row-smart-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-row-smart-0')), findsNothing);

    // Copy row 0: it lands under it, without the badge.
    await tester.longPress(find.text(first.rows[0]).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('live-row-copy')));
    await tester.pumpAndSettle();
    var grid = container.read(liveGridProvider);
    expect(grid.rows.length, first.rows.length + 1);
    expect(grid.rows[1], '${first.rows[0]} copy');
    expect(find.byKey(const ValueKey('live-row-smart-2')), findsOneWidget); // the program's row moved down

    // Delete the program's row: it warns, and the program loses the row.
    await tester.longPress(find.text(first.rows[1]).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Smart Program: Club'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-row-delete')));
    await tester.pumpAndSettle();
    expect(find.textContaining('The Smart Program Club plays this row'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-row-delete-confirm')));
    await tester.pumpAndSettle();
    grid = container.read(liveGridProvider);
    expect(grid.rows.length, first.rows.length);
    expect(grid.rowOf(first.rowIds[1]), isNull);
    expect(container.read(smartProgramsProvider).single.gridRows, isEmpty);

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

  // Tab S6 Lite (landscape / portrait) and P20 Pro (landscape / portrait) lay out cleanly, Grid and Mixer.
  for (final size in const [Size(1333, 800), Size(800, 1333), Size(746, 360), Size(360, 740)]) {
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
      // Project save sits in the header, as on the other main screens.
      expect(find.byIcon(Icons.save_outlined), findsOneWidget);
      // And the Mixer.
      await tester.tap(find.byIcon(Icons.view_column));
      await tester.pumpAndSettle();
      expect(find.text('GO'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.pump(const Duration(milliseconds: 300));
    });
  }
}
