import 'package:dmx_controller/core/audio/beat_source.dart';
import 'package:dmx_controller/core/song/song_show_player.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_group.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/layer.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/song_show.dart';
import 'package:dmx_controller/state/artnet_providers.dart';
import 'package:dmx_controller/state/audio_providers.dart';
import 'package:dmx_controller/state/fixture_group_providers.dart';
import 'package:dmx_controller/state/fixture_providers.dart';
import 'package:dmx_controller/state/song_show_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAudio implements SongAudio {
  @override
  Duration length = const Duration(minutes: 3);
  @override
  Duration position = Duration.zero;
  @override
  Future<void> load(String path) async {}
  @override
  void play(Duration from) {}
  @override
  void stop() {}
  @override
  void seek(Duration to) {}
}

class _SilentBeats implements BeatSource {
  @override
  Stream<DateTime> get beatEvents => const Stream.empty();
  @override
  bool get isListening => false;
  @override
  String? get lastError => null;
  @override
  Future<bool> start() async => false;
  @override
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final par = FixtureProfile(
    id: 'par',
    name: 'PAR',
    category: FixtureCategory.rgb,
    channels: const [
      FixtureChannel(offset: 0, function: ChannelFunction.dimmer),
      FixtureChannel(offset: 1, function: ChannelFunction.red),
    ],
  );

  ProviderContainer makeContainer() {
    final container = ProviderContainer(overrides: [
      activeBeatSourceProvider.overrideWithValue(_SilentBeats()),
      songShowPlayerProvider.overrideWith((ref) {
        final player = SongShowPlayer(audio: _FakeAudio(), sink: LayerCueSink(ref.read));
        ref.onDispose(player.dispose);
        return player;
      }),
    ]);
    addTearDown(container.dispose);
    container.read(patchedFixturesProvider.notifier).loadAll([
      for (var i = 0; i < 4; i++)
        PatchedFixture(id: 'f$i', label: 'P$i', profile: par, universeId: 'u1', startChannel: i * 2),
    ]);
    container.read(fixtureGroupsProvider.notifier).loadAll(const [
      FixtureGroup(id: 'front', name: 'Front', iconKey: 'all', fixtureIds: ['f0', 'f1']),
    ]);
    return container;
  }

  SongShow show({List<String> groups = const []}) => SongShow(
    id: 's',
    name: 'Song',
    audio: const SongAudioRef(fileName: 'a.mp3', durationMs: 1000, path: '/a.mp3'),
    groupIds: groups,
    cues: const [SongCue(id: 'c', atBeat: 0, layerId: layer1Id, action: SongCueAction.stop)],
  );

  test('a show limited to a group scopes its layers while it plays and frees them when it stops', () async {
    final container = makeContainer();
    final service = container.read(artNetServiceProvider);

    expect(await startSongShow(container.read, show(groups: ['front'])), isNull);
    expect(service.layerIsScoped(layer1Id), isTrue);
    expect(container.read(playingSongShowIdProvider), 's');

    stopSongShow(container.read);
    expect(service.layerIsScoped(layer1Id), isFalse);
    expect(container.read(playingSongShowIdProvider), isNull);
  });

  test('a show with no groups leaves the layers unscoped', () async {
    final container = makeContainer();
    expect(await startSongShow(container.read, show()), isNull);
    expect(container.read(artNetServiceProvider).layerIsScoped(layer1Id), isFalse);
    stopSongShow(container.read);
  });

  test('changing the groups of the running show takes effect straight away', () async {
    final container = makeContainer();
    final service = container.read(artNetServiceProvider);
    await startSongShow(container.read, show());
    expect(service.layerIsScoped(layer1Id), isFalse);

    updateRunningSongShow(container.read, show(groups: ['front']));
    expect(service.layerIsScoped(layer1Id), isTrue);

    updateRunningSongShow(container.read, show());
    expect(service.layerIsScoped(layer1Id), isFalse);
    stopSongShow(container.read);
  });

  test('a group that no longer exists does not silence the show', () async {
    final container = makeContainer();
    await startSongShow(container.read, show(groups: ['deleted']));
    expect(container.read(artNetServiceProvider).layerIsScoped(layer1Id), isFalse);
    stopSongShow(container.read);
  });

  test('starting another show ends the first one and its scope', () async {
    final container = makeContainer();
    final service = container.read(artNetServiceProvider);
    await startSongShow(container.read, show(groups: ['front']));
    expect(service.layerIsScoped(layer1Id), isTrue);
    const other = SongShow(
      id: 'o',
      name: 'Other',
      audio: SongAudioRef(fileName: 'b.mp3', durationMs: 1000, path: '/b.mp3'),
      cues: [SongCue(id: 'c', atBeat: 0, layerId: layer2Id, action: SongCueAction.stop)],
    );
    await startSongShow(container.read, other);
    expect(service.layerIsScoped(layer1Id), isFalse);
    expect(container.read(playingSongShowIdProvider), 'o');
    stopSongShow(container.read);
  });
}
