import '../../models/song_show.dart';

/// How far a placed or dragged cue is pulled to the beat grid.
enum SongSnap {
  off('Free', 0),
  beat('1 beat', 1),
  half('½ beat', 0.5),
  bar('1 bar', 4);

  const SongSnap(this.label, this.beats);
  final String label;
  final double beats;

  double apply(double beat) {
    final value = beats == 0 ? beat : (beat / beats).round() * beats;
    return value < 0 ? 0 : value;
  }
}

/// Maps between beats and horizontal pixels on the timeline.
class TimelineScale {
  final double pixelsPerBeat;

  const TimelineScale(this.pixelsPerBeat);

  static const minPixelsPerBeat = 6.0;
  static const maxPixelsPerBeat = 120.0;

  double x(double beat) => beat * pixelsPerBeat;
  double beatAt(double x) => x / pixelsPerBeat;

  TimelineScale zoomed(double factor) =>
      TimelineScale((pixelsPerBeat * factor).clamp(minPixelsPerBeat, maxPixelsPerBeat));
}

/// A cue and how far its block reaches: until the next cue on the same layer,
/// or the end of the timeline. A stop has no length of its own to show.
class CueSpan {
  final SongCue cue;
  final double endBeat;

  const CueSpan(this.cue, this.endBeat);
}

/// The blocks to draw on [layerId]'s lane.
List<CueSpan> cueSpans(SongShow show, String layerId, double timelineEndBeat) {
  final onLayer = [for (final c in show.sortedCues) if (c.layerId == layerId) c];
  return [
    for (var i = 0; i < onLayer.length; i++)
      CueSpan(onLayer[i], i + 1 < onLayer.length ? onLayer[i + 1].atBeat : timelineEndBeat),
  ];
}

/// How many beats the timeline needs to show: the audio, anything placed past
/// it, and a bar's breathing room, never less than 16 bars.
double timelineBeats(SongShow show) {
  var end = 64.0;
  final audio = show.audio;
  if (audio != null && audio.durationMs > 0) {
    final beats = show.beatAtMs(audio.durationMs.toDouble());
    if (beats > end) end = beats;
  }
  for (final c in show.cues) {
    if (c.atBeat + 8 > end) end = c.atBeat + 8;
  }
  for (final s in show.sections) {
    if (s.endBeat > end) end = s.endBeat;
  }
  return end.ceilToDouble();
}

/// Where a bank-button press during recording lands: the song position, on
/// the grid.
double recordBeat(SongShow show, Duration position, SongSnap snap) =>
    snap.apply(show.beatAtMs(position.inMicroseconds / 1000));

/// Tempo from a run of tap times (milliseconds). Needs at least two taps;
/// uses the average gap of the most recent ones. Null when there is no usable
/// run (fewer than two taps, or the last gap shows the run was abandoned).
double? tapTempo(List<int> tapsMs, {int window = 8}) {
  if (tapsMs.length < 2) return null;
  final recent = tapsMs.length > window ? tapsMs.sublist(tapsMs.length - window) : tapsMs;
  final span = recent.last - recent.first;
  if (span <= 0) return null;
  final bpm = (recent.length - 1) * 60000 / span;
  return bpm < 40 || bpm > 250 ? null : bpm;
}

/// The zoom a two-finger pinch gives: [base] pixels per beat when the fingers
/// were [startDistance] apart, scaled by how far apart they are now, within
/// the zoom limits.
double pinchPixelsPerBeat(double base, double startDistance, double distance) {
  if (startDistance <= 0) return base;
  return (base * distance / startDistance).clamp(TimelineScale.minPixelsPerBeat, TimelineScale.maxPixelsPerBeat);
}

/// The horizontal scroll offset that keeps [focalBeat] under the point
/// [focalX] pixels from the left of the view at [pixelsPerBeat] — so a pinch
/// zooms around the fingers, not around the start of the song.
double scrollOffsetForFocal(double focalBeat, double focalX, double pixelsPerBeat) {
  final offset = focalBeat * pixelsPerBeat - focalX;
  return offset < 0 ? 0 : offset;
}
