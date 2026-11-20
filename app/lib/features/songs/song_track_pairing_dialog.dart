import 'package:flutter/material.dart';

import '../../core/audio/osc_beat_source.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/l10n.dart';

/// Pairs a song show with a Rekordbox track for Song watch: title and artist
/// as rkbx_link names them, typed in or taken from the master deck. Pops
/// `(title, artist)`, both empty to clear the pairing.
class SongTrackPairingDialog extends StatefulWidget {
  final String title;
  final String artist;
  final RkbxDeckState Function() nowPlaying;

  const SongTrackPairingDialog({super.key, required this.title, required this.artist, required this.nowPlaying});

  @override
  State<SongTrackPairingDialog> createState() => _SongTrackPairingDialogState();
}

class _SongTrackPairingDialogState extends State<SongTrackPairingDialog> {
  late final _title = TextEditingController(text: widget.title);
  late final _artist = TextEditingController(text: widget.artist);
  String? _note;

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    super.dispose();
  }

  void _useNowPlaying() {
    final deck = widget.nowPlaying();
    if (!deck.hasTrack) {
      setState(() => _note = context.l10n.songTrackNothingPlaying);
      return;
    }
    setState(() {
      _note = null;
      _title.text = deck.title!.trim();
      _artist.text = (deck.artist ?? '').trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.songTrackPairing),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.songTrackPairingHint, style: const TextStyle(fontSize: 11.5, color: AppColors.textDim)),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('pairing-title'),
              controller: _title,
              decoration: InputDecoration(labelText: l.songTrackTitle),
            ),
            TextField(
              key: const ValueKey('pairing-artist'),
              controller: _artist,
              decoration: InputDecoration(labelText: l.songTrackArtist),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const ValueKey('pairing-now-playing'),
              icon: const Icon(Icons.album_outlined, size: 18),
              label: Text(l.songTrackUseNowPlaying),
              onPressed: _useNowPlaying,
            ),
            if (_note != null) ...[
              const SizedBox(height: 4),
              Text(_note!, style: const TextStyle(fontSize: 11, color: AppColors.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, ('', '')), child: Text(l.songWatchClear)),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.commonCancel)),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_title.text.trim(), _artist.text.trim())),
          child: Text(l.commonSave),
        ),
      ],
    );
  }
}
