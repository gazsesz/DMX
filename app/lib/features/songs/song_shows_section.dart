import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/play_toggle_card.dart';
import '../../core/theme/app_colors.dart';
import '../../models/song_show.dart';
import '../../state/song_show_providers.dart';
import 'song_show_actions.dart';
import 'song_show_editor_screen.dart';
import '../../l10n/l10n.dart';

/// The Song Shows block on the Chases screen: one row per timed program, a
/// play button on each, and + to make a new one.
class SongShowsSection extends ConsumerWidget {
  const SongShowsSection({super.key});

  String _subtitle(SongShow show) {
    final parts = <String>[
      '${show.bpm.round()} BPM',
      if (show.audio != null && show.audio!.durationMs > 0) _clock(show.audio!.durationMs),
      '${show.cues.length} ${show.cues.length == 1 ? 'cue' : 'cues'}',
      if (show.audio == null) 'no audio linked',
    ];
    return parts.join(' · ');
  }

  String _clock(int ms) {
    final s = (ms / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _open(BuildContext context, String id) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => SongShowEditorScreen(showId: id)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shows = ref.watch(songShowsProvider);
    final playingId = ref.watch(playingSongShowIdProvider);

    Future<void> toggle(SongShow show) async {
      if (playingId == show.id) {
        stopSongShow(ref.read);
        return;
      }
      final error = await startSongShow(ref.read, show);
      if (error != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
    }

    Future<void> delete(SongShow show) async {
      final ok = await confirmDeleteSongShow(context, show);
      if (!ok) return;
      if (playingId == show.id) stopSongShow(ref.read);
      ref.read(songShowsProvider.notifier).remove(show.id);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              context.l10n.dashSongShowsHeader,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint, letterSpacing: 1),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const ValueKey('import-song-show'),
                  icon: const Icon(Icons.file_open_outlined, size: 20),
                  tooltip: context.l10n.songImportASongShow,
                  onPressed: () => importSongShowFromFile(context, ref),
                ),
                IconButton(
                  key: const ValueKey('new-song-show'),
                  icon: const Icon(Icons.add, size: 20),
                  tooltip: context.l10n.songNewSongShow,
                  onPressed: () {
                    final show = ref.read(songShowsProvider.notifier).create(context.l10n.songNewSongShow);
                    _open(context, show.id);
                  },
                ),
              ],
            ),
          ],
        ),
        Text(
          context.l10n.songAProgramTimedTo,
          style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
        ),
        const SizedBox(height: 8),
        if (shows.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(context.l10n.songNoSongShowsYet, style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
          )
        else
          for (final show in shows)
            PlayToggleCard(
              key: ValueKey('song-show-${show.id}'),
              toggleKey: ValueKey('song-toggle-${show.id}'),
              active: playingId == show.id,
              icon: Icons.music_note,
              accent: AppColors.accent2,
              accentOn: AppColors.accent2On,
              onToggle: () => toggle(show),
              onOpen: () => _open(context, show.id),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(show.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        Text(_subtitle(show), style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
                      ],
                    ),
                  ),
                  IconButton(
                    key: ValueKey('export-song-${show.id}'),
                    icon: const Icon(Icons.ios_share, size: 18),
                    tooltip: context.l10n.filesExport,
                    onPressed: () => exportSongShowToFile(context, ref, show),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    tooltip: context.l10n.scDuplicate,
                    onPressed: () => ref.read(songShowsProvider.notifier).duplicate(show.id),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: context.l10n.scDelete,
                    onPressed: () => delete(show),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
