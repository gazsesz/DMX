import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/osc_beat_source.dart';
import '../../core/song/song_follower.dart';
import '../../core/song/song_match.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/l10n.dart';
import '../../state/audio_providers.dart';
import '../../state/song_show_providers.dart';
import '../../state/song_watch_providers.dart';

/// "Artist – Title", or just the title.
String trackLabel(String? title, String? artist) {
  final t = (title ?? '').trim();
  final a = (artist ?? '').trim();
  return a.isEmpty ? t : '$a – $t';
}

/// Setup's Song watch card: the switch, what the master deck is playing and
/// whether a show will follow it, the light delay, and a live list of what
/// rkbx_link is sending — so its config can be checked from the tablet.
class SongWatchCard extends ConsumerStatefulWidget {
  const SongWatchCard({super.key});

  @override
  ConsumerState<SongWatchCard> createState() => _SongWatchCardState();
}

class _SongWatchCardState extends ConsumerState<SongWatchCard> {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final prefs = ref.watch(songWatchPrefsProvider);
    final notifier = ref.read(songWatchPrefsProvider.notifier);
    final status = ref.watch(songWatchStatusProvider);
    final source = ref.watch(oscBeatSourceProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: const ValueKey('song-watch-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(l.songWatchTitle),
              subtitle: Text(l.songWatchSubtitle, style: const TextStyle(fontSize: 11)),
              value: prefs.enabled,
              onChanged: notifier.setEnabled,
            ),
            const SizedBox(height: 6),
            Text(
              '${l.songWatchConfig}\n'
              '  osc.msg.master/time true',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.textDim),
            ),
            if (prefs.enabled) ...[
              const SizedBox(height: 10),
              _statusLine(context, status, source),
              const SizedBox(height: 10),
              Text(l.songWatchOffset(prefs.offsetMs.toString()), style: const TextStyle(fontSize: 12)),
              Slider(
                min: -500,
                max: 500,
                divisions: 100,
                value: prefs.offsetMs.toDouble().clamp(-500, 500),
                label: '${prefs.offsetMs} ms',
                onChanged: (v) => notifier.setOffsetMs(v.round()),
              ),
              Text(l.songWatchOffsetHint, style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint)),
              const SizedBox(height: 6),
              _Monitor(source: source),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusLine(BuildContext context, SongWatchStatus status, OscBeatSource source) {
    final l = context.l10n;
    final deck = source.deck;
    final lastAt = source.lastMessageAt;
    final recent = lastAt != null && DateTime.now().difference(lastAt) < const Duration(seconds: 3);
    final String text;
    var color = AppColors.textFaint;
    if (status.phase == SongWatchPhase.following) {
      text = l.songWatchFollowing(trackLabel(status.title, status.artist), status.showName ?? '');
      color = AppColors.success;
    } else if (!recent) {
      text = l.songWatchNoData;
    } else if (!deck.hasTrack) {
      text = l.songWatchNoTitle;
      color = AppColors.danger;
    } else {
      final track = trackLabel(deck.title, deck.artist);
      final show = matchSongShow(ref.read(songShowsProvider), title: deck.title ?? '', artist: deck.artist ?? '');
      text = show == null ? l.songWatchNoShow(track) : l.songWatchReady(track, show.name);
      if (show != null) color = AppColors.accent2;
    }
    return Text(text, key: const ValueKey('song-watch-status'), style: TextStyle(fontSize: 11.5, color: color));
  }
}

class _Monitor extends StatelessWidget {
  final OscBeatSource source;

  const _Monitor({required this.source});

  @override
  Widget build(BuildContext context) {
    final seen = source.seenAddresses;
    final deck = source.deck;
    final time = deck.timeSec;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(context.l10n.songWatchMonitor, style: const TextStyle(fontSize: 12)),
      children: [
        if (time != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${trackLabel(deck.title, deck.artist)}  ${_clock(time)}  ×${deck.rate.toStringAsFixed(3)}',
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        if (seen.isEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(context.l10n.songWatchMonitorEmpty, style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
          )
        else
          for (final s in seen)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${s.address}  ${s.lastValue}  (${s.count})',
                style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: AppColors.textDim),
              ),
            ),
      ],
    );
  }

  static String _clock(double seconds) {
    final total = seconds.floor();
    final ms = ((seconds - total) * 10).floor();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}.$ms';
  }
}
