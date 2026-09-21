import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback/chase_player.dart';
import '../core/playback/smart_program_player.dart';
import 'artnet_providers.dart';
import 'momentary_fx_providers.dart';
import 'provider_reader.dart';
import 'audio_providers.dart';

/// A single player shared by every screen that can start a bank/chase
/// (Dashboard triggers, the Banks "Run Bank" preview, the Chase editor's
/// "Preview"). Starting playback anywhere always cleanly supersedes
/// whatever was already running elsewhere, instead of two independent
/// loops racing over the same universes.
final playbackControllerProvider = Provider<ChasePlayer>((ref) {
  final player = ChasePlayer();
  ref.onDispose(player.dispose);
  return player;
});

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

final nowPlayingProvider = StateProvider<NowPlaying?>((ref) => null);

/// Kills everything: both players, every channel on every universe, and the
/// now-playing state. Shared by the Dashboard's panic button, the control
/// dock and the remote endpoint so they can't drift apart.
Future<void> blackoutEverything(ReadProvider read) async {
  // First: a held Freeze pushes its own frame over the top of everything
  // else on the way out, blackout included. The panic button has to win.
  read(momentaryFxProvider.notifier).releaseAll();
  read(playbackControllerProvider).stop();
  read(smartProgramPlayerProvider).stop();
  final service = read(artNetServiceProvider);
  if (!service.isConnected) {
    await service.connect(read(artNetSettingsProvider));
  }
  service.blackoutAll(read(universesProvider));
  read(nowPlayingProvider.notifier).state = null;
}

/// Stops whatever is playing without blacking the rig out — the fixtures
/// hold their current look.
void stopPlayback(ReadProvider read) {
  read(playbackControllerProvider).stop();
  read(smartProgramPlayerProvider).stop();
  read(nowPlayingProvider.notifier).state = null;
}
