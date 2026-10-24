import 'package:dmx_controller/core/song/cue_resize.dart';
import 'package:dmx_controller/models/smart_program.dart';
import 'package:dmx_controller/models/song_show.dart';
import 'package:flutter_test/flutter_test.dart';

SongCue start(String id, double beat, {String layer = 'l1'}) =>
    SongCue(id: id, atBeat: beat, layerId: layer, target: const ProgramTarget(id: 'b', isBank: true));

SongCue stop(String id, double beat, {String layer = 'l1'}) =>
    SongCue(id: id, atBeat: beat, layerId: layer, action: SongCueAction.stop);

SongShow show(List<SongCue> cues) => SongShow(id: 's', name: 'S', cues: cues);

void main() {
  var n = 0;
  String newId() => 'new${n++}';

  List<(String, double, SongCueAction)> summary(List<SongCue> cues, {String layer = 'l1'}) => [
    for (final c in (cues.where((c) => c.layerId == layer).toList()..sort((a, b) => a.atBeat.compareTo(b.atBeat))))
      (c.id, c.atBeat, c.action),
  ];

  test('with nothing after it, dragging the end adds a Stop there', () {
    final s = show([start('a', 4)]);
    final cues = resizeCueEnd(s, s.cues.first, 12, newId: newId)!;
    final added = cues.singleWhere((c) => c.action == SongCueAction.stop);
    expect(added.atBeat, 12);
    expect(added.layerId, 'l1');
    expect(cues.where((c) => c.id == 'a'), hasLength(1), reason: 'the look stays');
  });

  test('with a Stop after it, the Stop moves', () {
    final s = show([start('a', 4), stop('s', 12)]);
    final cues = resizeCueEnd(s, s.cues.first, 20, newId: newId)!;
    expect(summary(cues), [('a', 4.0, SongCueAction.start), ('s', 20.0, SongCueAction.stop)]);
  });

  test('with another look straight after it, the hand-over point moves', () {
    final s = show([start('a', 4), start('b', 12)]);
    final cues = resizeCueEnd(s, s.cues.first, 8, newId: newId)!;
    expect(summary(cues), [('a', 4.0, SongCueAction.start), ('b', 8.0, SongCueAction.start)]);
  });

  test('the end never passes the cue after the one that ends it', () {
    final s = show([start('a', 4), stop('s', 12), start('c', 20)]);
    final cues = resizeCueEnd(s, s.cues.first, 99, newId: newId)!;
    expect(cues.singleWhere((c) => c.id == 's').atBeat, 19.5);
  });

  test('the end never gets closer than half a beat to the start', () {
    final s = show([start('a', 4), stop('s', 12)]);
    final cues = resizeCueEnd(s, s.cues.first, 1, newId: newId)!;
    expect(cues.singleWhere((c) => c.id == 's').atBeat, 4.5);
    final lone = show([start('a', 4)]);
    final added = resizeCueEnd(lone, lone.cues.first, 4, newId: newId)!.singleWhere((c) => c.action == SongCueAction.stop);
    expect(added.atBeat, 4.5);
  });

  test('only the same layer counts, and a stop has no end to move', () {
    final s = show([start('a', 4), start('other', 6, layer: 'l2')]);
    final cues = resizeCueEnd(s, s.cues.first, 10, newId: newId)!;
    expect(cues.where((c) => c.layerId == 'l2'), hasLength(1), reason: 'the other layer is untouched');
    expect(cues.where((c) => c.layerId == 'l1' && c.action == SongCueAction.stop), hasLength(1));
    expect(resizeCueEnd(show([stop('s', 4)]), stop('s', 4), 8, newId: newId), isNull);
  });

  test('no room between a look and the one after it changes nothing', () {
    final s = show([start('a', 4), start('b', 4.2), start('c', 4.5)]);
    expect(resizeCueEnd(s, s.cues.first, 8, newId: newId), isNull);
  });
}
