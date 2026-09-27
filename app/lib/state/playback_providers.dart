import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback/chase_player.dart';
import '../core/playback/smart_program_player.dart';
import '../models/bank.dart';
import '../models/chase.dart';
import '../models/layer.dart';
import 'artnet_providers.dart';
import 'bank_providers.dart';
import 'fixture_providers.dart';
import 'layer_providers.dart';
import 'momentary_fx_providers.dart';
import 'provider_reader.dart';
import 'audio_providers.dart';
import 'scene_providers.dart';
import 'tempo_providers.dart';

/// One independent [ChasePlayer] per layer id — Layer 1's entry is what
/// [playbackControllerProvider] aliases to below, so every pre-existing
/// consumer of that name keeps working unchanged. Starting a bank/chase on
/// one layer never supersedes whatever another layer is running; the layers
/// stay conflict-free as long as the scenes each one plays leave the
/// channels the others own out of [Scene.fixtureValues] — e.g. one layer
/// runs a color/beam chase on a moving head while another runs a slow
/// pan/tilt sweep on the same fixture, each only ever writing its own
/// attributes (see the Scene editor's "INCLUDES" toggles).
final chasePlayerProvider = Provider.family<ChasePlayer, String>((ref, layerId) {
  final player = ChasePlayer();
  ref.onDispose(player.dispose);
  return player;
});

/// What's running on a given layer id, mirroring the old per-layer
/// StateProviders this replaces.
final nowPlayingForLayerProvider = StateProvider.family<NowPlaying?, String>((ref, layerId) => null);

/// A single player shared by every screen that can start a bank/chase
/// (Dashboard triggers, the Banks "Run Bank" preview, the Chase editor's
/// "Preview"). Starting playback anywhere always cleanly supersedes
/// whatever was already running elsewhere, instead of two independent
/// loops racing over the same universes.
final playbackControllerProvider = chasePlayerProvider(layer1Id);

/// The single Smart Program runner, sharing the same [ChasePlayer] above —
/// so a Smart Program's tempo-driven chase switches use the exact same
/// "only one thing plays" machinery as a plain bank/chase trigger. Anything
/// that starts a *plain* trigger directly on [playbackControllerProvider]
/// must call `stop()` on this first, since this player's own beat listener
/// would otherwise try to reassert its chase on the next beat.
final smartProgramPlayerProvider = Provider<SmartProgramPlayer>((ref) {
  final player = SmartProgramPlayer(
    chasePlayer: ref.watch(playbackControllerProvider),
    beatService: ref.watch(activeBeatSourceProvider),
    // Read, not watched: the program is driven from callbacks, and a
    // rebuilt player would drop the running show on the floor.
    beatSyncEnabled: () => ref.read(beatSyncEnabledProvider),
    beatRate: () => ref.read(beatRateProvider),
    flashLength: () => ref.read(flashLengthProvider),
    // Routed through the shared predictor so a Smart Program's tempo
    // tracking rides out a missed beat the same way a beat-synced chase
    // does, instead of the classifier alone having to fold it back in.
    beatEvents: ref.watch(beatPredictorProvider).events,
    // Lets the player suspend the app-wide Auto-Fade switch for as long as
    // a Beat Flash bank is the active zone, and put it back once the
    // program moves off it — see `SmartProgramPlayer._updateAutoFadeSuppression`.
    isAutoFadeOn: () => ref.read(tempoProvider).autoFade,
    setAutoFade: (value) => ref.read(tempoProvider.notifier).setAutoFade(value),
  );
  ref.onDispose(player.dispose);
  return player;
});

/// The running Smart Program's zone and live tempo, for anything that isn't
/// the Dashboard — the control dock shows which part of a program is
/// playing, which is the thing you actually want to know from another tab.
final smartProgramStatusProvider = StreamProvider<SmartProgramStatus>((ref) {
  return ref.watch(smartProgramPlayerProvider).statusStream;
});

/// The last thing that played, remembered after it stops.
///
/// [nowPlayingProvider] goes null on stop, which is correct for "what is
/// running" but leaves the dock's Start button with nothing to resume. This
/// shadows it and simply never clears.
///
/// It has to be *alive* before the first trigger fires, or it misses it —
/// Riverpod builds a provider on first read, and by then the thing to
/// remember may already have stopped. [watchLastPlayed] does that once at
/// startup; don't rely on the dock being on screen to bring it into
/// existence.
final lastPlayedProvider = StateNotifierProvider<LastPlayedNotifier, NowPlaying?>((ref) {
  final notifier = LastPlayedNotifier();
  ref.listen<NowPlaying?>(
    nowPlayingProvider,
    (_, next) {
      if (next != null) notifier.remember(next);
    },
    fireImmediately: true,
  );
  return notifier;
});

class LastPlayedNotifier extends StateNotifier<NowPlaying?> {
  LastPlayedNotifier() : super(null);

  void remember(NowPlaying playing) => state = playing;
}

/// Brings [lastPlayedProvider] into existence so it starts listening.
/// Called once at startup — see that provider for why it can't wait.
void watchLastPlayed(ReadProvider read) => read(lastPlayedProvider);

/// Which bottom-nav/rail section is currently visible. AppShell keeps every
/// section's screen mounted (via IndexedStack) so switching tabs doesn't
/// reset their state — but that means a screen owning a "preview while
/// editing" style playback (e.g. Banks' Run Bank button) never sees a
/// normal `dispose()` when the user navigates away, so it needs this to
/// notice it's no longer the visible tab and stop itself.
final activeSectionIndexProvider = StateProvider<int>((ref) => 0);

enum PlaybackKind { bank, chase, smartProgram }

/// What's currently active on the shared player, if anything — the single
/// source of truth for "what's running" so Dashboard, Banks and Chases all
/// agree on it instead of each screen tracking its own local flag (which is
/// how a bank/chase started from one tab used to show as inactive on every
/// other tab). Also drives the small status banner shown when navigating
/// away from the Dashboard.
class NowPlaying {
  final String id;
  final PlaybackKind kind;
  final String name;

  const NowPlaying({required this.id, required this.kind, required this.name});

  bool get isBank => kind == PlaybackKind.bank;
}

final nowPlayingProvider = nowPlayingForLayerProvider(layer1Id);

/// Kills everything: every layer's player, every channel on every universe,
/// and every layer's now-playing state. Shared by the Dashboard's panic
/// button, the control dock and the remote endpoint so they can't drift
/// apart.
Future<void> blackoutEverything(ReadProvider read) async {
  // First: a held Freeze pushes its own frame over the top of everything
  // else on the way out, blackout included. The panic button has to win.
  read(momentaryFxProvider.notifier).releaseAll();
  for (final layer in read(layersProvider)) {
    read(chasePlayerProvider(layer.id)).stop();
    read(nowPlayingForLayerProvider(layer.id).notifier).state = null;
  }
  read(smartProgramPlayerProvider).stop();
  final service = read(artNetServiceProvider);
  if (!service.isConnected) {
    await service.connect(read(artNetSettingsProvider));
  }
  service.blackoutAll(read(universesProvider));
}

/// Stops whatever is playing without blacking the rig out — the fixtures
/// hold their current look.
void stopPlayback(ReadProvider read) {
  for (final layer in read(layersProvider)) {
    read(chasePlayerProvider(layer.id)).stop();
    read(nowPlayingForLayerProvider(layer.id).notifier).state = null;
  }
  read(smartProgramPlayerProvider).stop();
}

/// Stops just [layerId]'s player and clears its now-playing state, leaving
/// every other layer untouched.
void stopLayer(WidgetRef ref, String layerId) {
  ref.read(chasePlayerProvider(layerId)).stop();
  ref.read(nowPlayingForLayerProvider(layerId).notifier).state = null;
}

/// Builds a synthetic one-step chase from [bank] (using the app's shared
/// tempo/beat settings, exactly like the Banks "Run Bank" button) and starts
/// it on [layerId]'s player. Returns an error message to show the user, or
/// null on success. Only stops the Smart Program player when targeting
/// [layer1Id] — that's the one player a Smart Program can reassert a chase
/// onto.
String? runBankOnLayer(WidgetRef ref, {required Bank bank, required String layerId}) {
  final service = ref.read(artNetServiceProvider);
  if (!service.isConnected) return 'Not connected — check Settings';
  if (layerId == layer1Id) ref.read(smartProgramPlayerProvider).stop();
  final beatSync = ref.read(beatSyncEnabledProvider);
  final tempo = ref.read(tempoProvider);
  final chase = Chase(
    id: 'bank-run-$layerId-${bank.id}',
    name: bank.name,
    steps: [ChaseStep(bankId: bank.id, hold: tempo.hold, fade: tempo.fade)],
    direction: ChaseDirection.forward,
    beatSync: beatSync,
  );
  ref.read(chasePlayerProvider(layerId)).play(
    chase: chase,
    scenes: ref.read(scenesProvider),
    banks: ref.read(banksProvider),
    patchedFixtures: ref.read(patchedFixturesProvider),
    universes: ref.read(universesProvider),
    service: service,
    beatStream: beatSync ? ref.read(beatDetectorProvider).beatEvents : null,
    beatRate: beatRateOf(ref),
    flashLength: ref.read(flashLengthProvider),
    liveBeatRate: () => ref.read(beatRateProvider),
    liveFlashLength: () => ref.read(flashLengthProvider),
    fadeOverride: () {
      final t = ref.read(tempoProvider);
      return t.autoFade ? t.fade : null;
    },
  );
  ref.read(nowPlayingForLayerProvider(layerId).notifier).state = NowPlaying(
    id: bank.id,
    kind: PlaybackKind.bank,
    name: bank.name,
  );
  return null;
}
