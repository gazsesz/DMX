import 'package:dmx_controller/core/song/song_show_player.dart';
import 'package:dmx_controller/core/song/song_timeline_math.dart';
import 'package:dmx_controller/features/songs/song_show_editor_screen.dart';
import 'package:dmx_controller/models/artnet_settings.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/layer.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/song_show.dart';
import 'package:dmx_controller/models/universe_config.dart';
import 'package:dmx_controller/state/artnet_providers.dart';
import 'package:dmx_controller/state/audio_providers.dart';
import 'package:dmx_controller/state/bank_providers.dart';
import 'package:dmx_controller/state/fixture_providers.dart';
import 'package:dmx_controller/state/playback_providers.dart';
import 'package:dmx_controller/state/scene_providers.dart';
import 'package:dmx_controller/state/song_show_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/silent_beats.dart';

class _Sink implements SongCueSink {
  final events = <String>[];
  @override
  void start(SongCue cue) => events.add('start');
  @override
  void stopLayer(String layerId, {Duration? blackoutFade}) =>
      events.add(blackoutFade == null ? 'hold $layerId' : 'blackout $layerId ${blackoutFade.inMilliseconds}');
}

class _Audio implements SongAudio {
  @override
  Duration length = const Duration(minutes: 1);
  @override
  Duration position = Duration.zero;
  @override
  Future<void> load(String path) async {}
  @override
  void play(Duration from) => position = from;
  @override
  void stop() {}
  @override
  void seek(Duration to) => position = to;
}

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
  await tester.tapAt(tester.getTopLeft(find.byKey(ValueKey(key))) + Offset(dx, 10));
  await tester.pumpAndSettle();
}

void main() {
  group('how a Stop ends', () {
    test('keeps the last look unless told to black out, and survives JSON and copying', () {
      const hold = SongCue(id: 'a', atBeat: 4, layerId: layer1Id, action: SongCueAction.stop);
      expect(hold.stopBlackout, isFalse);
      expect(hold.toJson().containsKey('blackout'), isFalse, reason: 'old files stay as they were');

      final dark = hold.asStop(blackout: true, fadeMs: 2000);
      final back = SongCue.fromJson(dark.toJson());
      expect(back.stopBlackout, isTrue);
      expect(back.stopFadeMs, 2000);
      final pasted = dark.duplicatedAs('b', atBeat: 9);
      expect(pasted.stopBlackout, isTrue);
      expect(pasted.stopFadeMs, 2000);
      expect(dark.copyWith(atBeat: 6).stopBlackout, isTrue, reason: 'moving it keeps how it ends');
      expect(SongCue.fromJson({'id': 'x', 'layerId': 'l', 'action': 'stop'}).stopBlackout, isFalse);
    });

    test('the player asks the sink for a blackout only on a blackout stop', () async {
      const show = SongShow(id: 's', name: 'S', cues: [
        SongCue(id: 'h', atBeat: 2, layerId: layer1Id, action: SongCueAction.stop),
        SongCue(id: 'd', atBeat: 4, layerId: layer2Id, action: SongCueAction.stop, stopBlackout: true, stopFadeMs: 1500),
      ]);
      final sink = _Sink();
      var wall = Duration.zero;
      final audio = _Audio();
      final player = SongShowPlayer(audio: audio, sink: sink, wall: () => wall);
      await player.play(show);
      sink.events.clear();
      for (var ms = 10; ms <= 2500; ms += 10) {
        wall = Duration(milliseconds: ms);
        audio.position = Duration(milliseconds: ms);
        player.tick();
      }
      expect(sink.events, ['hold $layer1Id', 'blackout $layer2Id 1500']);
      player.dispose();
    });
  });

  group('blackout on the rig', () {
    const universe = UniverseConfig(id: 'u1', name: 'U1', universe: 0);
    final head = FixtureProfile(
      id: 'head',
      name: 'Head',
      category: FixtureCategory.movingHead,
      channels: const [
        FixtureChannel(offset: 0, function: ChannelFunction.dimmer),
        FixtureChannel(offset: 1, function: ChannelFunction.pan),
      ],
    );

    test('fades the dimmer out but leaves pan where it was, and ends the layer', () async {
      final container = ProviderContainer(overrides: [activeBeatSourceProvider.overrideWithValue(SilentBeats())]);
      addTearDown(container.dispose);
      await container.read(artNetServiceProvider).connect(const ArtNetSettings(demoMode: true));
      container.read(universesProvider.notifier).loadAll(const [universe]);
      container.read(patchedFixturesProvider.notifier).loadAll([
        PatchedFixture(id: 'f0', label: 'H', profile: head, universeId: 'u1', startChannel: 0),
      ]);
      final scene = container.read(scenesProvider.notifier).create('Look', {
        'f0': {0: 200, 1: 128},
      });
      final service = container.read(artNetServiceProvider);

      previewSongCue(container.read, SongCue(id: 'c', atBeat: 0, layerId: layer1Id, sceneId: scene.id));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(service.getChannelValue(universe, 0), 200);
      expect(service.getChannelValue(universe, 1), 128);

      LayerCueSink(container.read).stopLayer(layer1Id, blackoutFade: const Duration(milliseconds: 400));
      expect(container.read(nowPlayingForLayerProvider(layer1Id)), isNull, reason: 'the layer is no longer playing');
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(service.getChannelValue(universe, 0), 0, reason: 'dark');
      expect(service.getChannelValue(universe, 1), 128, reason: 'the head did not swing');
      expect(container.read(chasePlayerProvider(layer1Id)).isPlaying, isFalse);
    });

    test('a plain stop leaves the look on stage', () async {
      final container = ProviderContainer(overrides: [activeBeatSourceProvider.overrideWithValue(SilentBeats())]);
      addTearDown(container.dispose);
      await container.read(artNetServiceProvider).connect(const ArtNetSettings(demoMode: true));
      container.read(universesProvider.notifier).loadAll(const [universe]);
      container.read(patchedFixturesProvider.notifier).loadAll([
        PatchedFixture(id: 'f0', label: 'H', profile: head, universeId: 'u1', startChannel: 0),
      ]);
      final scene = container.read(scenesProvider.notifier).create('Look', {
        'f0': {0: 200, 1: 128},
      });
      final service = container.read(artNetServiceProvider);
      previewSongCue(container.read, SongCue(id: 'c', atBeat: 0, layerId: layer1Id, sceneId: scene.id));
      await Future<void>.delayed(const Duration(milliseconds: 600));

      LayerCueSink(container.read).stopLayer(layer1Id);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(service.getChannelValue(universe, 0), 200, reason: 'the look is held');
    });
  });

  group('Stop dialog in the editor', () {
    testWidgets('a new Stop asks how it ends, and a blackout is saved with its fade', (tester) async {
      final container = await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
      await tapAtLane(tester, 'lane-tap-$layer1Id', 100);
      await tester.tap(find.byKey(const ValueKey('add-stop-cue')));
      await tester.pumpAndSettle();
      expect(find.text('How does it end?'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('stop-mode-blackout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('stop-fade-2000')));
      await tester.tap(find.byKey(const ValueKey('stop-mode-ok')));
      await tester.pumpAndSettle();

      final cue = container.read(songShowsProvider).single.cues.single;
      expect(cue.action, SongCueAction.stop);
      expect(cue.stopBlackout, isTrue);
      expect(cue.stopFadeMs, 2000);
      expect(find.text('Dark'), findsOneWidget, reason: 'the block says it is a blackout');
    });

    testWidgets('keeping the last look is the default choice', (tester) async {
      final container = await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
      await tapAtLane(tester, 'lane-tap-$layer1Id', 100);
      await tester.tap(find.byKey(const ValueKey('add-stop-cue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('stop-mode-ok')));
      await tester.pumpAndSettle();
      final cue = container.read(songShowsProvider).single.cues.single;
      expect(cue.stopBlackout, isFalse);
      expect(find.text('Stop'), findsWidgets);
    });

    testWidgets('an existing Stop can be changed from its menu', (tester) async {
      final container = await pumpEditor(
        tester,
        const SongShow(
          id: 's',
          name: 'Song',
          cues: [SongCue(id: 'x', atBeat: 3, layerId: layer1Id, action: SongCueAction.stop)],
        ),
      );
      await tester.tap(find.byKey(const ValueKey('cue-head-x')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cue-stop-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('stop-mode-blackout')));
      await tester.tap(find.byKey(const ValueKey('stop-mode-ok')));
      await tester.pumpAndSettle();
      final cue = container.read(songShowsProvider).single.cues.single;
      expect(cue.id, 'x');
      expect(cue.atBeat, 3);
      expect(cue.stopBlackout, isTrue);
      expect(cue.stopFadeMs, SongCue.defaultStopFadeMs);
    });
  });

  group('pinch to zoom', () {
    test('the zoom follows how far apart the fingers are, within the limits', () {
      expect(pinchPixelsPerBeat(32, 100, 200), 64);
      expect(pinchPixelsPerBeat(32, 100, 50), 16);
      expect(pinchPixelsPerBeat(32, 100, 100000), TimelineScale.maxPixelsPerBeat);
      expect(pinchPixelsPerBeat(32, 100, 1), TimelineScale.minPixelsPerBeat);
      expect(pinchPixelsPerBeat(32, 0, 50), 32, reason: 'no starting distance: no change');
    });

    test('the scroll keeps the beat under the fingers in place', () {
      // Beat 10 under a point 200 px from the left, zoomed to 40 px/beat.
      expect(scrollOffsetForFocal(10, 200, 40), 200);
      expect(scrollOffsetForFocal(1, 200, 10), 0, reason: 'never scrolls before the start');
    });

    testWidgets('two fingers moving apart zoom the timeline in', (tester) async {
      await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
      final lane = find.byKey(const ValueKey('lane-tap-$layer1Id'));
      final before = tester.getSize(lane).width;
      final center = tester.getTopLeft(find.byKey(const ValueKey('timeline-ruler'))) + const Offset(300, 12);

      final a = await tester.startGesture(center - const Offset(40, 0), pointer: 1);
      final b = await tester.startGesture(center + const Offset(40, 0), pointer: 2);
      await a.moveBy(const Offset(-60, 0));
      await b.moveBy(const Offset(60, 0));
      await tester.pump();
      await tester.pump();
      await a.up();
      await b.up();
      await tester.pumpAndSettle();

      expect(tester.getSize(lane).width, greaterThan(before * 1.5));
    });

    testWidgets('and moving together zoom it out', (tester) async {
      await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
      final lane = find.byKey(const ValueKey('lane-tap-$layer1Id'));
      final before = tester.getSize(lane).width;
      final center = tester.getTopLeft(find.byKey(const ValueKey('timeline-ruler'))) + const Offset(300, 12);

      final a = await tester.startGesture(center - const Offset(100, 0), pointer: 1);
      final b = await tester.startGesture(center + const Offset(100, 0), pointer: 2);
      await a.moveBy(const Offset(70, 0));
      await b.moveBy(const Offset(-70, 0));
      await tester.pump();
      await tester.pump();
      await a.up();
      await b.up();
      await tester.pumpAndSettle();

      expect(tester.getSize(lane).width, lessThan(before));
    });

    testWidgets('a pinch over a cue zooms and does not move the cue', (tester) async {
      final container = await pumpEditor(tester, const SongShow(id: 's', name: 'Song'));
      container.read(banksProvider.notifier).addBank();
      await tapAtLane(tester, 'lane-tap-$layer1Id', 70);
      await tester.tap(find.byKey(const ValueKey('add-stop-cue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('stop-mode-ok')));
      await tester.pumpAndSettle();
      final cue = container.read(songShowsProvider).single.cues.single;
      final head = tester.getCenter(find.byKey(ValueKey('cue-head-${cue.id}')));

      final a = await tester.startGesture(head - const Offset(8, 0), pointer: 1);
      final b = await tester.startGesture(head + const Offset(8, 0), pointer: 2);
      await a.moveBy(const Offset(-40, 0));
      await b.moveBy(const Offset(40, 0));
      await tester.pump();
      await a.up();
      await b.up();
      await tester.pumpAndSettle();

      expect(container.read(songShowsProvider).single.cues.single.atBeat, cue.atBeat);
    });
  });
}
