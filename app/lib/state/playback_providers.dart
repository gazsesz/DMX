import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback/chase_player.dart';
import '../core/playback/smart_program_player.dart';
import 'artnet_providers.dart';
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
    beatService: ref.watch(beatDetectorProvider),
  );
  ref.onDispose(player.dispose);
  return player;
});

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
