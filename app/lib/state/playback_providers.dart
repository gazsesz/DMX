import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback/chase_player.dart';
import '../core/playback/smart_program_player.dart';
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

/// What the Dashboard has fired on the shared player, if anything — shown
/// as a small status banner from every screen so leaving the Dashboard
/// doesn't hide the fact that a bank/chase is still running.
class NowPlaying {
  final String name;
  final bool isBank;

  const NowPlaying({required this.name, required this.isBank});
}

final nowPlayingProvider = StateProvider<NowPlaying?>((ref) => null);
