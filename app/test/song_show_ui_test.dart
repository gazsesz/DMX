import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dmx_controller/core/widgets/control_dock.dart' show LiveStageDock;
import 'package:dmx_controller/features/songs/song_show_editor_screen.dart';
import 'support/silent_beats.dart';
import 'package:dmx_controller/features/songs/song_shows_section.dart';
import 'package:dmx_controller/features/songs/song_target_picker.dart' show resetSongPickFilter;
import 'package:dmx_controller/models/fixture_group.dart';
import 'package:dmx_controller/models/layer.dart';
import 'package:dmx_controller/models/song_show.dart';
import 'package:dmx_controller/state/audio_providers.dart';
import 'package:dmx_controller/state/bank_providers.dart';
import 'package:dmx_controller/state/chase_providers.dart';
import 'package:dmx_controller/state/control_dock_providers.dart';
import 'package:dmx_controller/state/scene_providers.dart';
import 'package:dmx_controller/state/fixture_group_providers.dart';
import 'package:dmx_controller/state/song_show_providers.dart';
import 'package:dmx_controller/state/song_view_providers.dart' show resetSongViewCache;

Future<ProviderContainer> pumpEditor(WidgetTester tester, SongShow show) async {
  final container = ProviderContainer(overrides: [activeBeatSourceProvider.overrideWithValue(SilentBeats())]);
  addTearDown(container.dispose);
  container.read(songShowsProvider.notifier).upsert(show);
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: SongShowEditorScreen(showId: show.id)),
  ));
  await tester.pump();
  return container;
}

Future<void> tapAtLane(WidgetTester tester, String key, double dx) async {
  final finder = find.byKey(ValueKey(key));
  await tester.tapAt(tester.getTopLeft(finder) + Offset(dx, 10));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    resetSongPickFilter();
    resetSongViewCache();
  });
  scopeAndImportTests();
  cueBlockTests();
  transportAndPickerTests();
  resizeByFingerTests();
  liveStageTests();
  testWidgets('the list shows and deletes song shows', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: SongShowsSection()))),
    ));
    expect(find.text('No song shows yet'), findsOneWidget);

    container.read(songShowsProvider.notifier).upsert(const SongShow(
      id: 'a',
      name: 'Opener',
      bpm: 128,
      audio: SongAudioRef(fileName: 'o.mp3', durationMs: 200000),
    ));
    await tester.pump();
    expect(find.text('Opener'), findsOneWidget);
    expect(find.text('128 BPM · 3:20 · 0 cues'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(container.read(songShowsProvider), isEmpty);
  });

  testWidgets('the + button makes a show and opens its editor', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: SongShowsSection()))),
    ));
    await tester.tap(find.byKey(const ValueKey('new-song-show')));
    await tester.pumpAndSettle();
    expect(container.read(songShowsProvider), hasLength(1));
    expect(find.byKey(const ValueKey('song-pick-audio')), findsOneWidget);
  });

  testWidgets('tapping a lane adds a stop cue on the grid, and a tap on it can delete it', (tester) async {
    final container = await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
    await tapAtLane(tester, 'lane-tap-$layer1Id', 100); // 100 px / 32 = beat 3.1 -> 3
    await tester.tap(find.byKey(const ValueKey('add-stop-cue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stop-mode-ok')));
    await tester.pumpAndSettle();
    final cue = container.read(songShowsProvider).single.cues.single;
    expect(cue.action, SongCueAction.stop);
    expect(cue.atBeat, 3);
    expect(cue.layerId, layer1Id);

    await tester.tap(find.byKey(ValueKey('cue-${cue.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cue-delete')));
    await tester.pumpAndSettle();
    expect(container.read(songShowsProvider).single.cues, isEmpty);
  });

  testWidgets('a start cue takes the bank picked from the dialog', (tester) async {
    final container = await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
    final bank = container.read(banksProvider.notifier).addBank();
    await tapAtLane(tester, 'lane-tap-$layer1Id', 200);
    await tester.tap(find.byKey(const ValueKey('add-start-cue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('target-bank-${bank.id}')));
    await tester.pumpAndSettle();
    final cue = container.read(songShowsProvider).single.cues.single;
    expect(cue.action, SongCueAction.start);
    expect(cue.target!.bankId, bank.id);
    expect(cue.atBeat, 6);
  });

  testWidgets('a section can be added, edited and deleted', (tester) async {
    final container = await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
    await tapAtLane(tester, 'timeline-sections', 320); // beat 10
    await tester.tap(find.byKey(const ValueKey('section-kind-build')));
    await tester.tap(find.byKey(const ValueKey('section-save')));
    await tester.pumpAndSettle();
    var s = container.read(songShowsProvider).single.sections.single;
    expect(s.kind, SongSectionKind.build);
    expect(s.startBeat, 10);
    expect(s.lengthBeats, 16);

    await tester.tap(find.byKey(const ValueKey('section-10.0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('section-longer')));
    await tester.tap(find.byKey(const ValueKey('section-save')));
    await tester.pumpAndSettle();
    s = container.read(songShowsProvider).single.sections.single;
    expect(s.lengthBeats, 20);

    await tester.tap(find.byKey(const ValueKey('section-10.0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('section-delete')));
    await tester.pumpAndSettle();
    expect(container.read(songShowsProvider).single.sections, isEmpty);
  });

}

void scopeAndImportTests() {
  testWidgets('limiting the show to a group is saved with it, and All fixtures clears it', (tester) async {
    final container = await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
    container.read(fixtureGroupsProvider.notifier).loadAll(const [
      FixtureGroup(id: 'front', name: 'Front', iconKey: 'all', fixtureIds: ['f0']),
    ]);
    expect(find.text('All fixtures'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('song-scope')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scope-front')));
    await tester.tap(find.byKey(const ValueKey('scope-done')));
    await tester.pumpAndSettle();
    expect(container.read(songShowsProvider).single.groupIds, ['front']);
    expect(find.text('1 group'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('song-scope')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All fixtures').last);
    await tester.pumpAndSettle();
    expect(container.read(songShowsProvider).single.groupIds, isEmpty);
  });

  testWidgets('an imported show says its song file has to be linked, and keeps its cues', (tester) async {
    await pumpEditor(
      tester,
      const SongShow(id: 's', name: 'Song', audio: SongAudioRef(fileName: 'opener.mp3', durationMs: 200000)),
    );
    expect(find.byKey(const ValueKey('audio-banner')), findsOneWidget);
    expect(find.textContaining('opener.mp3'), findsWidgets);
  });

  testWidgets('the list offers import and export', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(songShowsProvider.notifier).upsert(const SongShow(id: 'a', name: 'Opener'));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: SongShowsSection()))),
    ));
    expect(find.byKey(const ValueKey('import-song-show')), findsOneWidget);
    expect(find.byKey(const ValueKey('export-song-a')), findsOneWidget);
  });
}

void cueBlockTests() {
  testWidgets('a Stop can be placed along a bank that plays to the end of the lane', (tester) async {
    final container = await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
    final bank = container.read(banksProvider.notifier).addBank();

    // The bank at beat 2: its block now covers the lane to the right.
    await tapAtLane(tester, 'lane-tap-$layer1Id', 70);
    await tester.tap(find.byKey(const ValueKey('add-start-cue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('target-bank-${bank.id}')));
    await tester.pumpAndSettle();
    expect(container.read(songShowsProvider).single.cues, hasLength(1));

    // A tap well to the right, over the faded tail, still adds a cue.
    await tapAtLane(tester, 'lane-tap-$layer1Id', 330); // beat 10
    await tester.tap(find.byKey(const ValueKey('add-stop-cue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stop-mode-ok')));
    await tester.pumpAndSettle();
    final cues = container.read(songShowsProvider).single.cues;
    expect(cues, hasLength(2), reason: 'the bank is still there');
    expect(cues.where((c) => c.action == SongCueAction.start).single.target!.bankId, bank.id);
    final stop = cues.singleWhere((c) => c.action == SongCueAction.stop);
    expect(stop.atBeat, 10);
  });

  testWidgets('tapping the head of a cue opens its menu, which no longer offers to turn it into a stop', (tester) async {
    final container = await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
    final bank = container.read(banksProvider.notifier).addBank();
    await tapAtLane(tester, 'lane-tap-$layer1Id', 70);
    await tester.tap(find.byKey(const ValueKey('add-start-cue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('target-bank-${bank.id}')));
    await tester.pumpAndSettle();

    final cue = container.read(songShowsProvider).single.cues.single;
    await tester.tap(find.byKey(ValueKey('cue-head-${cue.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cue-change')), findsOneWidget);
    expect(find.byKey(const ValueKey('cue-delete')), findsOneWidget);
    expect(find.byKey(const ValueKey('cue-make-stop')), findsNothing);
  });

  testWidgets('the screen explains how cues work', (tester) async {
    await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
    expect(find.byKey(const ValueKey('timeline-hint')), findsOneWidget);
    expect(find.textContaining('add a Stop to end it'), findsOneWidget);
  });
}

void transportAndPickerTests() {
  testWidgets('Play on an empty show without a song asks for some cues first', (tester) async {
    await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
    await tester.tap(find.byKey(const ValueKey('transport-play')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Add some cues'), findsOneWidget);
  });

  testWidgets('a show without a song plays silently from the bottom bar, and Stop ends it', (tester) async {
    final container = await pumpEditor(
      tester,
      const SongShow(
        id: 's',
        name: 'Song',
        cues: [SongCue(id: 'c', atBeat: 0, layerId: layer1Id, action: SongCueAction.stop)],
      ),
    );
    expect(find.text('Play'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('transport-play')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(playingSongShowIdProvider), 's');
    expect(find.text('Stop'), findsWidgets);
    expect(find.textContaining('Playing'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('transport-play')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(playingSongShowIdProvider), isNull);
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('the picker lists banks, scenes and chases and narrows them by filter and search', (tester) async {
    final container = await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
    final bank = container.read(banksProvider.notifier).addBank(name: 'Warm bank');
    final scene = container.read(scenesProvider.notifier).create('Red wash', {});
    container.read(scenesProvider.notifier).create('Blue wash', {});
    final chase = container.read(chasesProvider.notifier).create('Rainbow run');
    await tapAtLane(tester, 'lane-tap-$layer1Id', 100);
    await tester.tap(find.byKey(const ValueKey('add-start-cue')));
    await tester.pumpAndSettle();

    expect(find.byKey(ValueKey('target-bank-${bank.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('target-scene-${scene.id}')), findsOneWidget);
    await tester.drag(find.descendant(of: find.byType(AlertDialog), matching: find.byType(ListView)).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('target-chase-${chase.id}')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pick-filter-scenes')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('target-bank-${bank.id}')), findsNothing);
    expect(find.byKey(ValueKey('target-chase-${chase.id}')), findsNothing);
    expect(find.byKey(ValueKey('target-scene-${scene.id}')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('target-search')), 'blue');
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('target-scene-${scene.id}')), findsNothing);
    expect(find.text('Blue wash'), findsOneWidget);
  });

  testWidgets('a scene can be picked for a cue, and copied from the picker first', (tester) async {
    final container = await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
    final scene = container.read(scenesProvider.notifier).create('Red wash', {});
    await tapAtLane(tester, 'lane-tap-$layer1Id', 100);
    await tester.tap(find.byKey(const ValueKey('add-start-cue')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('copy-scene-${scene.id}')));
    await tester.pumpAndSettle();
    expect(container.read(scenesProvider).map((s) => s.name), ['Red wash', 'Red wash Copy']);

    await tester.tap(find.byKey(ValueKey('target-scene-${scene.id}')));
    await tester.pumpAndSettle();
    final cue = container.read(songShowsProvider).single.cues.single;
    expect(cue.sceneId, scene.id);
    expect(cue.target, isNull);
    expect(find.text('Red wash'), findsWidgets, reason: 'the block is named after the scene');
  });

  testWidgets('the picker offers a new scene', (tester) async {
    await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
    await tapAtLane(tester, 'lane-tap-$layer1Id', 100);
    await tester.tap(find.byKey(const ValueKey('add-start-cue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('new-scene')), findsOneWidget);
  });

  testWidgets('a cue can be copied and pasted onto another lane', (tester) async {
    final container = await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
    // A stop cue on layer 1 at beat 3 to copy.
    await tapAtLane(tester, 'lane-tap-$layer1Id', 100);
    await tester.tap(find.byKey(const ValueKey('add-stop-cue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stop-mode-ok')));
    await tester.pumpAndSettle();
    final cue = container.read(songShowsProvider).single.cues.single;

    await tester.tap(find.byKey(ValueKey('cue-head-${cue.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cue-copy')));
    await tester.pumpAndSettle();

    await tapAtLane(tester, 'lane-tap-$layer2Id', 320); // beat 10 on layer 2
    expect(find.byKey(const ValueKey('paste-cue')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('paste-cue')));
    await tester.pumpAndSettle();
    final cues = container.read(songShowsProvider).single.cues;
    expect(cues, hasLength(2));
    final pasted = cues.singleWhere((c) => c.id != cue.id);
    expect(pasted.layerId, layer2Id);
    expect(pasted.atBeat, 10);
    expect(pasted.action, SongCueAction.stop);
  });

  testWidgets('the cue menu offers Try it, Copy and Delete for a start cue', (tester) async {
    final container = await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
    final scene = container.read(scenesProvider.notifier).create('Red wash', {});
    await tapAtLane(tester, 'lane-tap-$layer1Id', 100);
    await tester.tap(find.byKey(const ValueKey('add-start-cue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('target-scene-${scene.id}')));
    await tester.pumpAndSettle();
    final cue = container.read(songShowsProvider).single.cues.single;
    await tester.tap(find.byKey(ValueKey('cue-head-${cue.id}')));
    await tester.pumpAndSettle();
    for (final key in ['cue-try', 'cue-stop-layer', 'cue-change', 'cue-copy', 'cue-delete']) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
  });
}

Future<SongCue> placeBank(WidgetTester tester, ProviderContainer container, double dx) async {
  final bank = container.read(banksProvider.notifier).addBank();
  await tapAtLane(tester, 'lane-tap-$layer1Id', dx);
  await tester.tap(find.byKey(const ValueKey('add-start-cue')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('target-bank-${bank.id}')));
  await tester.pumpAndSettle();
  return container.read(songShowsProvider).single.cues.single;
}

void resizeByFingerTests() {
  testWidgets('holding a look and dragging its end puts a Stop where the finger lets go', (tester) async {
    final container = await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
    final cue = await placeBank(tester, container, 70); // beat 2
    final head = tester.getCenter(find.byKey(ValueKey('cue-head-${cue.id}')));

    final gesture = await tester.startGesture(head);
    await tester.pump(const Duration(milliseconds: 700)); // long enough to be a hold
    expect(find.byKey(const ValueKey('resize-label')), findsOneWidget, reason: 'the end is picked up');
    await gesture.moveBy(const Offset(300, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('resize-label')), findsNothing);
    final cues = container.read(songShowsProvider).single.cues;
    expect(cues, hasLength(2));
    final stop = cues.singleWhere((c) => c.action == SongCueAction.stop);
    expect(stop.layerId, layer1Id);
    expect(stop.atBeat, 13);
    expect(cues.singleWhere((c) => c.id == cue.id).atBeat, 2, reason: 'the look itself did not move');
  });

  testWidgets('holding anywhere along a look moves the Stop that ends it', (tester) async {
    final container = await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
    final cue = await placeBank(tester, container, 70); // beat 2
    // A Stop at beat 10, added the way a person would.
    await tapAtLane(tester, 'lane-tap-$layer1Id', 330);
    await tester.tap(find.byKey(const ValueKey('add-stop-cue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stop-mode-ok')));
    await tester.pumpAndSettle();
    expect(container.read(songShowsProvider).single.cues, hasLength(2));

    // Hold on the faded tail (beat ~7.8), well right of the head, and drag on.
    final lane = tester.getTopLeft(find.byKey(ValueKey('lane-tap-$layer1Id')));
    final gesture = await tester.startGesture(lane + const Offset(250, 22));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(96, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final cues = container.read(songShowsProvider).single.cues;
    expect(cues, hasLength(2), reason: 'moved, not added');
    expect(cues.singleWhere((c) => c.action == SongCueAction.stop).atBeat, 11);
    expect(cues.singleWhere((c) => c.id == cue.id).action, SongCueAction.start);
  });

  testWidgets('a quick tap on the head still opens the menu, and a plain drag still moves the cue', (tester) async {
    final container = await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
    final cue = await placeBank(tester, container, 70);
    await tester.tap(find.byKey(ValueKey('cue-head-${cue.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cue-change')), findsOneWidget);
    await tester.tapAt(const Offset(5, 5)); // dismiss the sheet
    await tester.pumpAndSettle();

    await tester.drag(find.byKey(ValueKey('cue-head-${cue.id}')), const Offset(128, 0));
    await tester.pumpAndSettle();
    final cues = container.read(songShowsProvider).single.cues;
    expect(cues, hasLength(1), reason: 'a plain drag moves the cue, it does not grow a Stop');
    expect(cues.single.atBeat, inInclusiveRange(4, 6), reason: 'dragged about 4 beats right (less the touch slop)');
  });
}

void liveStageTests() {
  testWidgets('the live stage can be switched on from the editor', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
    expect(find.byType(LiveStageDock), findsNothing);
    expect(container.read(controlDockProvider).stageVisible, isFalse);

    await tester.tap(find.byKey(const ValueKey('song-live-stage')));
    await tester.pump();
    expect(container.read(controlDockProvider).stageVisible, isTrue);
    expect(find.byType(LiveStageDock), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('song-live-stage')));
    await tester.pump();
    expect(find.byType(LiveStageDock), findsNothing);
  });
}
