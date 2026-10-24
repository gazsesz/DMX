import '../../models/song_show.dart';

/// The shortest a cue's stretch can be dragged to, in beats.
const minCueBeats = 0.5;

/// What dragging the end of [cue] to [endBeat] does to the lane, as the new
/// list of the show's cues — or null when [cue] has no end to move (it is a
/// stop itself, or there is no room between it and the cue after).
///
/// A cue lasts until the next cue on its layer, so its "end" is the place of
/// that next cue: with a Stop there, the Stop moves; with no cue after it, a
/// Stop is added; with another look straight after it, the hand-over point
/// moves (that look starts earlier or later). The end never goes past the cue
/// that follows, and never closer than [minCueBeats] to the cue's start.
List<SongCue>? resizeCueEnd(SongShow show, SongCue cue, double endBeat, {required String Function() newId}) {
  if (cue.action == SongCueAction.stop) return null;
  final lane = [for (final c in show.sortedCues) if (c.layerId == cue.layerId) c];
  final index = lane.indexWhere((c) => c.id == cue.id);
  if (index < 0) return null;
  final next = index + 1 < lane.length ? lane[index + 1] : null;
  final minEnd = cue.atBeat + minCueBeats;

  if (next == null) {
    final end = endBeat < minEnd ? minEnd : endBeat;
    return [
      ...show.cues,
      SongCue(id: newId(), atBeat: end, layerId: cue.layerId, action: SongCueAction.stop),
    ];
  }

  final following = index + 2 < lane.length ? lane[index + 2] : null;
  final maxEnd = following == null ? double.infinity : following.atBeat - minCueBeats;
  if (maxEnd < minEnd) return null;
  final end = endBeat.clamp(minEnd, maxEnd).toDouble();
  return [for (final c in show.cues) if (c.id == next.id) c.copyWith(atBeat: end) else c];
}
