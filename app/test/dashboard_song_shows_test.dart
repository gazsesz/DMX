import 'dart:io';

import 'package:dmx_controller/core/theme/app_theme.dart';
import 'package:dmx_controller/features/dashboard/dashboard_screen.dart';
import 'package:dmx_controller/models/dashboard_trigger.dart';
import 'package:dmx_controller/models/layer.dart';
import 'package:dmx_controller/models/song_show.dart';
import 'package:dmx_controller/state/audio_providers.dart';
import 'package:dmx_controller/state/bank_providers.dart';
import 'package:dmx_controller/state/dashboard_providers.dart';
import 'package:dmx_controller/state/smart_program_providers.dart';
import 'package:dmx_controller/state/song_show_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/silent_beats.dart';

SongShow show(String id, String name) => SongShow(
  id: id,
  name: name,
  bpm: 126,
  audio: const SongAudioRef(fileName: 'a.mp3', durationMs: 200000),
  cues: const [SongCue(id: 'c', atBeat: 0, layerId: layer1Id, action: SongCueAction.stop)],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.createTempSync('dmx_dash').path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      (call) async => {'appName': 'DMX', 'packageName': 'x', 'version': '1.0.0', 'buildNumber': '1'},
    );
    messenger.setMockMethodCallHandler(const MethodChannel('com.llfbandit.record/messages'), (call) async => null);
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> pumpDashboard(WidgetTester tester) async {
    final container = ProviderContainer(overrides: [activeBeatSourceProvider.overrideWithValue(SilentBeats())]);
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final bank = container.read(banksProvider.notifier).addBank(name: 'Warm');
    container.read(dashboardTriggersProvider.notifier).add(bank.id, TriggerKind.bank);
    container.read(smartProgramsProvider.notifier).create('Night mode');
    container.read(songShowsProvider.notifier)
      ..upsert(show('a', 'Opener'))
      ..upsert(show('b', 'Closer'));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildAppTheme(), home: const DashboardScreen()),
    ));
    await tester.pump();
    return container;
  }

  double top(WidgetTester tester, String text) => tester.getTopLeft(find.text(text)).dy;

  testWidgets('the sections run Smart programs, Quick triggers, Song shows, then Layers', (tester) async {
    await pumpDashboard(tester);
    final smart = top(tester, 'SMART PROGRAMS');
    final quick = top(tester, 'QUICK TRIGGERS');
    final songs = top(tester, 'SONG SHOWS');
    final layers = top(tester, 'LAYERS');
    expect(smart, lessThan(quick));
    expect(quick, lessThan(songs));
    expect(songs, lessThan(layers));
  });

  testWidgets('each song show has a tile with its tempo, length and cue count', (tester) async {
    await pumpDashboard(tester);
    expect(find.text('Opener'), findsOneWidget);
    expect(find.text('Closer'), findsOneWidget);
    expect(find.text('126 BPM · 3:20'), findsNWidgets(2));
    expect(find.text('1 cue · silent'), findsNWidgets(2));
  });

  testWidgets('tapping a song show tile plays it and tapping again stops it', (tester) async {
    final container = await pumpDashboard(tester);
    await tester.tap(find.text('Opener'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(playingSongShowIdProvider), 'a');

    await tester.tap(find.text('Opener'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(playingSongShowIdProvider), isNull);
  });

  testWidgets('a song show that cannot start says why', (tester) async {
    final container = await pumpDashboard(tester);
    container.read(songShowsProvider.notifier).upsert(const SongShow(id: 'empty', name: 'Empty one'));
    await tester.pump();
    await tester.tap(find.text('Empty one'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Add some cues'), findsOneWidget);
    expect(container.read(playingSongShowIdProvider), isNull);
  });

  testWidgets('the tiles can be reordered', (tester) async {
    final container = await pumpDashboard(tester);
    container.read(songShowsProvider.notifier).move(0, 1);
    await tester.pump();
    expect(container.read(songShowsProvider).map((s) => s.name), ['Closer', 'Opener']);
    final closer = tester.getTopLeft(find.text('Closer'));
    final opener = tester.getTopLeft(find.text('Opener'));
    expect(closer.dy < opener.dy || (closer.dy == opener.dy && closer.dx < opener.dx), isTrue, reason: 'the tiles follow');

    // Out-of-range moves do nothing.
    container.read(songShowsProvider.notifier).move(0, 9);
    container.read(songShowsProvider.notifier).move(-1, 0);
    expect(container.read(songShowsProvider).map((s) => s.name), ['Closer', 'Opener']);
  });

  testWidgets('with no song shows the block says where to make one', (tester) async {
    final container = await pumpDashboard(tester);
    container.read(songShowsProvider.notifier).loadAll(const []);
    await tester.pump();
    expect(find.text('SONG SHOWS'), findsOneWidget);
    expect(find.text('None yet — create one from the Chase tab'), findsNWidgets(1));
  });
}
