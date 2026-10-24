import '../../models/song_show.dart';

/// The cues that fall in the window after [fromMs] up to and including
/// [toMs], in timeline order. Cues in disabled sections never fire.
List<SongCue> cuesDue(SongShow show, double fromMs, double toMs) {
  if (toMs <= fromMs) return const [];
  return [
    for (final c in show.activeCues)
      if (show.msOfBeat(c.atBeat) > fromMs && show.msOfBeat(c.atBeat) <= toMs) c,
  ];
}

/// What each layer should be doing at [ms], for starting mid-song or after a
/// seek: per layer, the last cue at or before [ms], kept only when it is a
/// start (a layer whose last cue was a stop is simply quiet). Ordered by the
/// layers' own cue times.
List<SongCue> stateAt(SongShow show, double ms) {
  final lastPerLayer = <String, SongCue>{};
  for (final c in show.activeCues) {
    if (show.msOfBeat(c.atBeat) <= ms) lastPerLayer[c.layerId] = c;
  }
  return [
    for (final c in lastPerLayer.values)
      if (c.action == SongCueAction.start && c.target != null) c,
  ];
}

/// Layers whose most recent cue at [ms] is a stop, or that have no cue yet
/// but are used by the show — what a seek has to silence.
Set<String> layersToSilence(SongShow show, double ms) {
  final all = {for (final c in show.cues) c.layerId};
  final playing = {for (final c in stateAt(show, ms)) c.layerId};
  return all.difference(playing);
}
