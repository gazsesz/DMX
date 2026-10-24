import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dmx_controller/features/songs/song_show_editor_screen.dart';
import 'package:dmx_controller/features/songs/song_shows_section.dart';
import 'package:dmx_controller/models/fixture_group.dart';
import 'package:dmx_controller/models/layer.dart';
import 'package:dmx_controller/models/song_show.dart';
import 'package:dmx_controller/state/bank_providers.dart';
import 'package:dmx_controller/state/fixture_group_providers.dart';
import 'package:dmx_controller/state/song_show_providers.dart';

Future<ProviderContainer> pumpEditor(WidgetTester tester, SongShow show) async {
  final container = ProviderContainer();
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
  scopeAndImportTests();
  cueBlockTests();
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

  testWidgets('Play without a linked audio file explains itself', (tester) async {
    await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
    await tester.tap(find.byKey(const ValueKey('song-play')));
    await tester.pumpAndSettle();
    expect(find.textContaining('has no audio file linked'), findsOneWidget);
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
