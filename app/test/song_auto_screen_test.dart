import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dmx_controller/core/song/song_analysis.dart';
import 'package:dmx_controller/features/songs/song_auto_screen.dart';
import 'package:dmx_controller/models/layer.dart';
import 'package:dmx_controller/models/smart_program.dart';
import 'package:dmx_controller/models/song_show.dart';
import 'package:dmx_controller/state/bank_providers.dart';
import 'package:dmx_controller/state/song_show_providers.dart';

const analysis = SongAnalysis(
  bpm: 126.5,
  beatOffsetMs: 80,
  tempoConfidence: 0.8,
  barLevel: [0.1, 0.1],
  barLow: [0.1, 0.1],
  sections: [
    SongSection(startBeat: 0, lengthBeats: 32, kind: SongSectionKind.intro),
    SongSection(startBeat: 32, lengthBeats: 64, kind: SongSectionKind.drop),
  ],
);

Future<ProviderContainer> pumpAuto(WidgetTester tester, SongShow show, {bool failAnalysis = false}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  container.read(songShowsProvider.notifier).upsert(show);
  final calm = container.read(banksProvider.notifier).addBank(name: 'Slow wash');
  container.read(banksProvider.notifier).setSlot(calm.id, 0, 'scene');
  final hot = container.read(banksProvider.notifier).addBank(name: 'Strobe');
  container.read(banksProvider.notifier).setSlot(hot.id, 0, 'scene');
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SongAutoScreen(
                showId: show.id,
                analyse: (path) async {
                  if (failAnalysis) throw StateError('cannot decode');
                  return analysis;
                },
              ),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return container;
}

const linked = SongShow(id: 's', name: 'Song', audio: SongAudioRef(fileName: 'a.mp3', durationMs: 1000, path: '/x/a.mp3'));

void main() {
  testWidgets('shows what the analysis found', (tester) async {
    await pumpAuto(tester, linked);
    expect(find.textContaining('126.5 BPM'), findsOneWidget);
    expect(find.textContaining('2 sections'), findsOneWidget);
  });

  testWidgets('"Tempo and sections only" keeps the cues', (tester) async {
    final cue = SongCue(id: 'c', atBeat: 4, layerId: layer1Id, target: const ProgramTarget(id: 'b', isBank: true));
    final container = await pumpAuto(tester, SongShow(id: 's', name: 'Song', audio: linked.audio, cues: [cue]));
    await tester.tap(find.byKey(const ValueKey('apply-analysis')));
    await tester.pumpAndSettle();
    final s = container.read(songShowsProvider).single;
    expect(s.bpm, 126.5);
    expect(s.beatOffsetMs, 80);
    expect(s.sections, hasLength(2));
    expect(s.cues.single.id, 'c');
  });

  testWidgets('"Generate show" fills the timeline with an automatic show', (tester) async {
    final container = await pumpAuto(tester, linked);
    await tester.tap(find.byKey(const ValueKey('generate-show')));
    await tester.pumpAndSettle();
    final s = container.read(songShowsProvider).single;
    expect(s.origin, SongShowOrigin.auto);
    expect(s.cues, isNotEmpty);
    expect(s.cues.where((c) => c.layerId == layer1Id), isNotEmpty);
    expect(find.text('open'), findsOneWidget, reason: 'back on the previous screen');
  });

  testWidgets('generating over an existing timeline asks first, and Cancel changes nothing', (tester) async {
    final cue = SongCue(id: 'c', atBeat: 4, layerId: layer1Id, target: const ProgramTarget(id: 'b', isBank: true));
    final container = await pumpAuto(tester, SongShow(id: 's', name: 'Song', audio: linked.audio, cues: [cue]));
    await tester.tap(find.byKey(const ValueKey('generate-show')));
    await tester.pumpAndSettle();
    expect(find.text('Replace what is on the timeline?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(songShowsProvider).single.cues.single.id, 'c');
  });

  testWidgets('a failed analysis says so and offers a retry', (tester) async {
    await pumpAuto(tester, linked, failAnalysis: true);
    expect(find.textContaining('cannot decode'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('without a linked song it asks for one', (tester) async {
    await pumpAuto(tester, const SongShow(id: 's', name: 'Song'));
    expect(find.text('Link a song file in the editor first'), findsOneWidget);
  });
}
