import 'package:flutter_test/flutter_test.dart';
import 'package:dmx_controller/core/song/song_timeline_math.dart';
import 'package:dmx_controller/models/smart_program.dart';
import 'package:dmx_controller/models/song_show.dart';

SongCue cue(String id, double beat, {String layer = 'l1'}) =>
    SongCue(id: id, atBeat: beat, layerId: layer, target: const ProgramTarget(id: 'b', isBank: true));

void main() {
  test('snap rounds to the grid and never goes negative', () {
    expect(SongSnap.beat.apply(3.4), 3);
    expect(SongSnap.beat.apply(3.6), 4);
    expect(SongSnap.half.apply(3.3), 3.5);
    expect(SongSnap.bar.apply(5.9), 4);
    expect(SongSnap.bar.apply(6.1), 8);
    expect(SongSnap.off.apply(3.37), 3.37);
    expect(SongSnap.beat.apply(-0.9), 0);
  });

  test('scale converts both ways and clamps zoom', () {
    const s = TimelineScale(20);
    expect(s.x(3), 60);
    expect(s.beatAt(60), 3);
    expect(s.zoomed(100).pixelsPerBeat, TimelineScale.maxPixelsPerBeat);
    expect(s.zoomed(0.001).pixelsPerBeat, TimelineScale.minPixelsPerBeat);
  });

  test('cue spans run to the next cue on the same layer', () {
    final show = SongShow(id: 's', name: 'n', cues: [cue('a', 0), cue('b', 8), cue('c', 4, layer: 'l2')]);
    final spans = cueSpans(show, 'l1', 64);
    expect([for (final s in spans) (s.cue.id, s.endBeat)], [('a', 8.0), ('b', 64.0)]);
  });

  test('timeline is at least 16 bars and grows with audio, cues and sections', () {
    expect(timelineBeats(const SongShow(id: 's', name: 'n')), 64);
    final long = SongShow(
      id: 's',
      name: 'n',
      audio: const SongAudioRef(fileName: 'a', durationMs: 300000),
      cues: [cue('a', 700)],
    );
    expect(timelineBeats(long), 708);
    const withSection = SongShow(
      id: 's',
      name: 'n',
      sections: [SongSection(startBeat: 60, lengthBeats: 40)],
    );
    expect(timelineBeats(withSection), 100);
  });

  test('record lands on the grid at the song position', () {
    const show = SongShow(id: 's', name: 'n', bpm: 120, beatOffsetMs: 0);
    expect(recordBeat(show, const Duration(milliseconds: 2230), SongSnap.beat), 4);
    expect(recordBeat(show, const Duration(milliseconds: 2230), SongSnap.off), closeTo(4.46, 1e-9));
  });

  test('tap tempo needs two taps and a sane rate', () {
    expect(tapTempo([0]), isNull);
    expect(tapTempo([0, 500, 1000, 1500]), closeTo(120, 1e-9));
    expect(tapTempo([0, 5000]), isNull, reason: '12 BPM is not a tempo');
  });
}
