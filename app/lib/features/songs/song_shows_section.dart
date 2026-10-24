import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/song_show.dart';
import '../../state/song_show_providers.dart';
import 'song_show_editor_screen.dart';

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
            const Text(
              'SONG SHOWS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint, letterSpacing: 1),
            ),
            IconButton(
              key: const ValueKey('new-song-show'),
              icon: const Icon(Icons.add, size: 20),
              tooltip: 'New song show',
              onPressed: () {
                final show = ref.read(songShowsProvider.notifier).create('New song show');
                _open(context, show.id);
              },
            ),
          ],
        ),
        const Text(
          'A program timed to one song: sections and cues placed on a timeline, played with the song',
          style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
        ),
        const SizedBox(height: 8),
        if (shows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No song shows yet', style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
          )
        else
          for (final show in shows)
            Card(
              key: ValueKey('song-show-${show.id}'),
              margin: const EdgeInsets.only(bottom: 8),
              color: playingId == show.id ? AppColors.accent2.withValues(alpha: 0.1) : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: playingId == show.id ? AppColors.accent2 : Colors.transparent, width: 1.5),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _open(context, show.id),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                  child: Row(
                    children: [
                      InkWell(
                        key: ValueKey('song-toggle-${show.id}'),
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => toggle(show),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: playingId == show.id ? AppColors.accent2 : AppColors.panel2,
                          ),
                          child: Icon(
                            playingId == show.id ? Icons.stop_rounded : Icons.music_note,
                            color: playingId == show.id ? AppColors.accent2On : AppColors.accent2,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
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
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        tooltip: 'Duplicate',
                        onPressed: () => ref.read(songShowsProvider.notifier).duplicate(show.id),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        tooltip: 'Delete',
                        onPressed: () => delete(show),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
