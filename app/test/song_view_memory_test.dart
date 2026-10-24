import 'package:dmx_controller/features/songs/song_show_editor_screen.dart';
import 'package:dmx_controller/models/layer.dart';
import 'package:dmx_controller/models/song_show.dart';
import 'package:dmx_controller/state/audio_providers.dart';
import 'package:dmx_controller/state/song_show_providers.dart';
import 'package:dmx_controller/state/song_view_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/silent_beats.dart';

/// A home screen with a button that opens the editor of [showId], so leaving
/// the editor is a real pop and opening it again a real push.
Future<ProviderContainer> pumpHome(WidgetTester tester, {List<String> shows = const ['s']}) async {
  final container = ProviderContainer(overrides: [activeBeatSourceProvider.overrideWithValue(SilentBeats())]);
  addTearDown(container.dispose);
  for (final id in shows) {
    container.read(songShowsProvider.notifier).upsert(SongShow(id: id, name: 'Song $id'));
  }
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              for (final id in shows)
                TextButton(
                  key: ValueKey('open-$id'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => SongShowEditorScreen(showId: id)),
                  ),
                  child: Text('open $id'),
                ),
            ],
          ),
        ),
      ),
    ),
  ));
  return container;
}

Future<void> open(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('open-$id')));
  await tester.pumpAndSettle();
}

Future<void> leave(WidgetTester tester) async {
  await tester.tap(find.byType(BackButton));
  await tester.pumpAndSettle();
}

double laneWidth(WidgetTester tester) => tester.getSize(find.byKey(const ValueKey('lane-tap-$layer1Id'))).width;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSongViewCache();
  });

  test('a view survives being written down and read back, and rubbish is ignored', () {
    const view = SongView(pixelsPerBeat: 47.5, scrollOffset: 310.25);
    final back = SongView.decode(view.encode())!;
    expect(back.pixelsPerBeat, 47.5);
    expect(back.scrollOffset, 310.25);
    expect(SongView.decode(null), isNull);
    expect(SongView.decode('nonsense'), isNull);
    expect(SongView.decode('0;5'), isNull);
    expect(SongView.decode('30;-4'), isNull);
  });

  testWidgets('the editor reopens at the zoom it was left at', (tester) async {
    await pumpHome(tester);
    await open(tester, 's');
    final first = laneWidth(tester);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    final zoomed = laneWidth(tester);
    expect(zoomed, greaterThan(first * 1.5));

    await leave(tester);
    await open(tester, 's');
    expect(laneWidth(tester), zoomed, reason: 'same zoom as when it was left');
  });

  testWidgets('and scrolled to the same place', (tester) async {
    await pumpHome(tester);
    await open(tester, 's');
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    final grab = tester.getTopLeft(find.byKey(const ValueKey('timeline-ruler'))) + const Offset(300, 12);
    await tester.dragFrom(grab, const Offset(-400, 0));
    await tester.pumpAndSettle();
    final left = tester.getTopLeft(find.byKey(const ValueKey('lane-tap-$layer1Id'))).dx;
    expect(left, lessThan(88), reason: 'it is scrolled (88 px is where the lanes start)');

    await leave(tester);
    await open(tester, 's');
    expect(tester.getTopLeft(find.byKey(const ValueKey('lane-tap-$layer1Id'))).dx, closeTo(left, 1));
  });

  testWidgets('each show remembers its own view', (tester) async {
    await pumpHome(tester, shows: const ['a', 'b']);
    await open(tester, 'a');
    final fresh = laneWidth(tester);
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    await leave(tester);

    await open(tester, 'b');
    expect(laneWidth(tester), fresh, reason: 'another show opens at the standard zoom');
    await leave(tester);

    await open(tester, 'a');
    expect(laneWidth(tester), greaterThan(fresh));
  });

  testWidgets('a new session opens at the zoom saved in the preferences', (tester) async {
    SharedPreferences.setMockInitialValues({
      songViewPrefKey('s'): const SongView(pixelsPerBeat: 80, scrollOffset: 0).encode(),
    });
    await pumpHome(tester);
    await open(tester, 's');
    await tester.pumpAndSettle();
    // 64 beats at 80 px each.
    expect(laneWidth(tester), 64 * 80);
  });

  testWidgets('the view is written to the preferences when the editor is left', (tester) async {
    await pumpHome(tester);
    await open(tester, 's');
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pumpAndSettle();
    await leave(tester);
    await tester.pumpAndSettle();
    final stored = SongView.decode((await SharedPreferences.getInstance()).getString(songViewPrefKey('s')));
    expect(stored, isNotNull);
    expect(stored!.pixelsPerBeat, closeTo(32 * 0.7, 0.01));
  });
}
