import 'package:dmx_controller/core/song/silent_song_audio.dart';
import 'package:dmx_controller/core/song/song_cue_scheduler.dart';
import 'package:dmx_controller/core/song/song_show_player.dart';
import 'package:dmx_controller/core/storage/song_show_io.dart';
import 'package:dmx_controller/models/artnet_settings.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/layer.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/scene.dart';
import 'package:dmx_controller/models/smart_program.dart';
import 'package:dmx_controller/models/song_show.dart';
import 'package:dmx_controller/models/universe_config.dart';
import 'package:dmx_controller/state/artnet_providers.dart';
import 'package:dmx_controller/state/audio_providers.dart';
import 'package:dmx_controller/state/fixture_providers.dart';
import 'package:dmx_controller/state/playback_providers.dart';
import 'package:dmx_controller/state/scene_providers.dart';
import 'package:dmx_controller/state/song_show_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/silent_beats.dart';

class _Sink implements SongCueSink {
  final events = <String>[];
  @override
  void start(SongCue cue) => events.add('start ${cue.sceneId ?? cue.target?.id}@${cue.layerId}');
  @override
  void stopLayer(String layerId) => events.add('stop $layerId');
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

void main() {
  const sceneCue = SongCue(id: 'c1', atBeat: 4, layerId: layer1Id, sceneId: 'scene-a');

  group('a cue that plays a scene', () {
    test('survives JSON and counts as having something to start', () {
      final back = SongCue.fromJson(sceneCue.toJson());
      expect(back.sceneId, 'scene-a');
      expect(back.target, isNull);
      expect(back.hasTarget, isTrue);
      expect(const SongCue(id: 's', atBeat: 0, layerId: 'l', action: SongCueAction.stop).hasTarget, isFalse);
    });

    test('changing what a cue starts replaces the old thing, never keeps both', () {
      final toBank = sceneCue.startingTarget(const ProgramTarget(id: 'b', isBank: true));
      expect(toBank.sceneId, isNull);
      expect(toBank.target!.bankId, 'b');
      final toScene = toBank.startingScene('scene-z');
      expect(toScene.target, isNull);
      expect(toScene.sceneId, 'scene-z');
      expect(toScene.id, 'c1');
      expect(toScene.atBeat, 4);
      expect(sceneCue.asStop().hasTarget, isFalse);
    });

    test('pasting makes a new cue with the same look somewhere else', () {
      final copy = sceneCue.duplicatedAs('c2', atBeat: 9, layerId: layer2Id);
      expect(copy.id, 'c2');
      expect(copy.atBeat, 9);
      expect(copy.layerId, layer2Id);
      expect(copy.sceneId, 'scene-a');
    });

    test('the scheduler and the player treat it like any other start', () async {
      const show = SongShow(id: 's', name: 'S', cues: [sceneCue]);
      expect(stateAt(show, 5000).single.sceneId, 'scene-a');

      final sink = _Sink();
      final player = SongShowPlayer(audio: _Audio(), sink: sink, wall: () => Duration.zero);
      await player.play(show, from: const Duration(seconds: 5));
      expect(sink.events, ['start scene-a@$layer1Id']);
      player.dispose();
    });

    test('usesScene says which show uses a scene', () {
      const show = SongShow(id: 's', name: 'S', cues: [sceneCue]);
      expect(show.usesScene('scene-a'), isTrue);
      expect(show.usesScene('other'), isFalse);
    });
  });

  group('silent playback', () {
    test('runs a clock from where it was started, stops where it was, and seeks', () {
      final watch = Stopwatch();
      final audio = SilentSongAudio(length: const Duration(minutes: 1), stopwatch: watch);
      expect(audio.position, Duration.zero);
      audio.play(const Duration(seconds: 10));
      expect(audio.position, greaterThanOrEqualTo(const Duration(seconds: 10)));
      audio.seek(const Duration(seconds: 30));
      expect(audio.position, greaterThanOrEqualTo(const Duration(seconds: 30)));
      audio.stop();
      final held = audio.position;
      expect(held, greaterThanOrEqualTo(const Duration(seconds: 30)));
      expect(audio.position, held, reason: 'stopped means it stays put');
    });
  });

  group('on the rig', () {
    const universe = UniverseConfig(id: 'u1', name: 'U1', universe: 0);
    final par = FixtureProfile(
      id: 'par',
      name: 'PAR',
      category: FixtureCategory.rgb,
      channels: const [
        FixtureChannel(offset: 0, function: ChannelFunction.dimmer),
        FixtureChannel(offset: 1, function: ChannelFunction.red),
      ],
    );

    test('Try it plays the scene on its layer, and Stop this layer ends it', () async {
      final container = ProviderContainer(overrides: [activeBeatSourceProvider.overrideWithValue(SilentBeats())]);
      addTearDown(container.dispose);
      await container.read(artNetServiceProvider).connect(const ArtNetSettings(demoMode: true));
      container.read(universesProvider.notifier).loadAll(const [universe]);
      container.read(patchedFixturesProvider.notifier).loadAll([
        PatchedFixture(id: 'f0', label: 'P', profile: par, universeId: 'u1', startChannel: 0),
      ]);
      final scene = container.read(scenesProvider.notifier).create('Red wash', {
        'f0': {0: 200, 1: 255},
      });

      previewSongCue(container.read, SongCue(id: 'c', atBeat: 0, layerId: layer1Id, sceneId: scene.id));
      expect(container.read(nowPlayingForLayerProvider(layer1Id))?.name, 'Red wash');
      expect(container.read(chasePlayerProvider(layer1Id)).isPlaying, isTrue);

      // Let the first (fading) step land on the stage.
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final service = container.read(artNetServiceProvider);
      expect(service.getChannelValue(universe, 1), 255);

      stopSongLayer(container.read, layer1Id);
      expect(container.read(chasePlayerProvider(layer1Id)).isPlaying, isFalse);
      expect(container.read(nowPlayingForLayerProvider(layer1Id)), isNull);
    });

    test('a scene that was deleted plays nothing and does no harm', () {
      final container = ProviderContainer(overrides: [activeBeatSourceProvider.overrideWithValue(SilentBeats())]);
      addTearDown(container.dispose);
      previewSongCue(container.read, const SongCue(id: 'c', atBeat: 0, layerId: layer1Id, sceneId: 'gone'));
      expect(container.read(nowPlayingForLayerProvider(layer1Id)), isNull);
    });
  });

  group('export and import with scene cues', () {
    final par = FixtureProfile(
      id: 'par',
      name: 'PAR',
      category: FixtureCategory.rgb,
      channels: const [FixtureChannel(offset: 0, function: ChannelFunction.dimmer)],
    );
    final rig = [PatchedFixture(id: 'f0', label: 'P1', profile: par, universeId: 'u1', startChannel: 0)];
    const scene = Scene(id: 'sc1', name: 'Red', fixtureValues: {
      'f0': {0: 255},
    });
    const layers = [Layer(id: layer1Id, name: 'Layer 1', priority: 1)];
    const show = SongShow(
      id: 'show',
      name: 'Scenes only',
      cues: [SongCue(id: 'c', atBeat: 0, layerId: layer1Id, sceneId: 'sc1')],
    );

    String export() => SongShowExport.collect(
      projectName: 'Club',
      show: show,
      allBanks: const [],
      allChases: const [],
      allScenes: const [scene],
      allFixtures: rig,
      allLayers: layers,
      allGroups: const [],
    ).encode();

    SongShowImport import({Set<String> sceneIds = const {}}) {
      var n = 0;
      return importSongShow(
        export(),
        fixtures: rig,
        layers: layers,
        groups: const [],
        banks: const [],
        chases: const [],
        sceneNames: {},
        sceneIds: sceneIds,
        songShowNames: {},
        newId: () => 'n${n++}',
      );
    }

    test('the scene travels with the show and the cue follows its copy', () {
      final result = import();
      expect(result.items, isNotNull);
      expect(result.items!.scenes.single.name, 'Red');
      expect(result.show.cues.single.sceneId, result.items!.scenes.single.id);
      expect(result.show.cues.single.sceneId, isNot('sc1'));
    });

    test('within the same project the scene is reused, not copied', () {
      final result = import(sceneIds: {'sc1'});
      expect(result.items, isNull);
      expect(result.show.cues.single.sceneId, 'sc1');
    });
  });
}
