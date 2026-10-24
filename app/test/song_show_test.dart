import 'package:flutter_test/flutter_test.dart';
import 'package:dmx_controller/core/song/song_clock.dart';
import 'package:dmx_controller/core/song/song_cue_scheduler.dart';
import 'package:dmx_controller/core/song/song_show_player.dart';
import 'package:dmx_controller/models/smart_program.dart';
import 'package:dmx_controller/models/project_data.dart';
import 'package:dmx_controller/models/song_show.dart';

SongCue start(String id, double beat, String bank, {String layer = 'l1'}) => SongCue(
  id: id,
  atBeat: beat,
  layerId: layer,
  target: ProgramTarget(id: bank, isBank: true),
);

// 120 BPM, no offset: one beat = 500 ms.
SongShow show({List<SongCue> cues = const [], List<SongSection> sections = const []}) =>
    SongShow(id: 's', name: 'Song', cues: cues, sections: sections);

class FakeAudio implements SongAudio {
  @override
  Duration length = const Duration(seconds: 60);
  @override
  Duration position = Duration.zero;
  final calls = <String>[];

  @override
  Future<void> load(String path) async => calls.add('load $path');
  @override
  void play(Duration from) {
    position = from;
    calls.add('play ${from.inMilliseconds}');
  }

  @override
  void stop() => calls.add('stop');
  @override
  void seek(Duration to) {
    position = to;
    calls.add('seek ${to.inMilliseconds}');
  }
}

class RecordingSink implements SongCueSink {
  final events = <String>[];
  @override
  void start(SongCue cue) => events.add('start ${cue.target!.id}@${cue.layerId}');
  @override
  void stopLayer(String layerId) => events.add('stop $layerId');
}

void main() {
  projectRoundTripTests();
  audioMatchTests();
  group('SongShow', () {
    test('JSON round trip keeps everything', () {
      final s = SongShow(
        id: 'a',
        name: 'One More Time',
        origin: SongShowOrigin.auto,
        audio: const SongAudioRef(fileName: 'x.mp3', durationMs: 5000, sha1: 'abc'),
        bpm: 122,
        beatOffsetMs: 40,
        sections: const [
          SongSection(startBeat: 0, lengthBeats: 16, kind: SongSectionKind.intro, label: 'Intro'),
          SongSection(startBeat: 16, lengthBeats: 32, kind: SongSectionKind.drop, enabled: false),
        ],
        cues: [
          start('c1', 0, 'bankA'),
          const SongCue(id: 'c2', atBeat: 8, layerId: 'l2', action: SongCueAction.stop),
          const SongCue(id: 'c3', atBeat: 9, layerId: 'l1', target: ProgramTarget(id: 'ch', isBank: false, lane: 'l2')),
        ],
        groupIds: const ['g1'],
      );
      final back = SongShow.fromJson(s.toJson());
      expect(back.toJson(), s.toJson());
      expect(back.cues[2].target, const ProgramTarget(id: 'ch', isBank: false, lane: 'l2'));
      expect(back.sections[1].enabled, isFalse);
    });

    test('an empty JSON map loads with defaults', () {
      final s = SongShow.fromJson({'id': 'x'});
      expect(s.bpm, 120);
      expect(s.cues, isEmpty);
    });

    test('beat and millisecond conversion honours bpm and offset', () {
      const s = SongShow(id: 'a', name: 'n', bpm: 120, beatOffsetMs: 100);
      expect(s.msOfBeat(4), 2100);
      expect(s.beatAtMs(2100), 4);
    });

    test('cues in a disabled section are not active', () {
      final s = show(
        cues: [start('a', 1, 'b1'), start('b', 20, 'b2')],
        sections: const [SongSection(startBeat: 16, lengthBeats: 16, enabled: false)],
      );
      expect(s.activeCues.map((c) => c.id), ['a']);
    });
  });

  group('scheduler', () {
    final s = show(cues: [
      start('a', 0, 'A'),
      start('b', 4, 'B'),
      const SongCue(id: 'c', atBeat: 8, layerId: 'l1', action: SongCueAction.stop),
      start('d', 4, 'D', layer: 'l2'),
    ]);

    test('cuesDue is half-open and ordered', () {
      expect(cuesDue(s, 0, 2000).map((c) => c.id), ['b', 'd']);
      expect(cuesDue(s, 2000, 4000).map((c) => c.id), ['c']);
      expect(cuesDue(s, 4000, 4000), isEmpty);
    });

    test('stateAt is the last start per layer', () {
      expect(stateAt(s, 2500).map((c) => c.id), ['b', 'd']);
      expect(stateAt(s, 4500).map((c) => c.id), ['d'], reason: 'l1 stopped at beat 8');
    });

    test('layersToSilence names layers with nothing playing', () {
      expect(layersToSilence(s, 4500), {'l1'});
      expect(layersToSilence(s, 0), {'l2'}, reason: 'l2 has no cue yet at 0');
    });
  });

  group('SongClock', () {
    ms(int v) => Duration(milliseconds: v);

    test('interpolates between stepped reports', () {
      final c = SongClock()..start(ms(1000), ms(0));
      c.report(ms(1000), ms(10));
      expect(c.now(ms(30)), ms(1030));
      c.report(ms(1047), ms(47));
      expect(c.now(ms(60)), ms(1060));
    });

    test('a report slightly behind does not run it backwards', () {
      final c = SongClock()..start(ms(0), ms(0));
      expect(c.now(ms(100)), ms(100));
      c.report(ms(80), ms(110)); // engine behind by ~30 ms
      expect(c.now(ms(110)), ms(100), reason: 'holds, never jumps back');
      expect(c.now(ms(200)), ms(170));
    });

    test('a large difference is a seek and jumps both ways', () {
      final c = SongClock()..start(ms(10000), ms(0));
      expect(c.now(ms(100)), ms(10100));
      c.report(ms(2000), ms(100));
      expect(c.now(ms(100)), ms(2000));
      c.report(ms(30000), ms(200));
      expect(c.now(ms(200)), ms(30000));
    });
  });

  group('SongShowPlayer', () {
    test('fires each cue once as the clock passes it', () async {
      final audio = FakeAudio();
      final sink = RecordingSink();
      var wall = Duration.zero;
      final player = SongShowPlayer(audio: audio, sink: sink, wall: () => wall);
      await player.play(show(cues: [start('a', 0, 'A'), start('b', 2, 'B')]));
      expect(sink.events, ['start A@l1'], reason: 'state at zero');

      for (var ms = 10; ms <= 1500; ms += 10) {
        wall = Duration(milliseconds: ms);
        audio.position = Duration(milliseconds: ms ~/ 47 * 47);
        player.tick();
      }
      expect(sink.events, ['start A@l1', 'start B@l1']);
      player.dispose();
    });

    test('seeking restores the look at the new position and silences idle layers', () async {
      final audio = FakeAudio();
      final sink = RecordingSink();
      var wall = Duration.zero;
      final player = SongShowPlayer(audio: audio, sink: sink, wall: () => wall);
      final s = show(cues: [start('a', 0, 'A'), start('b', 4, 'B'), start('d', 8, 'D', layer: 'l2')]);
      await player.play(s);
      sink.events.clear();

      player.seek(const Duration(seconds: 3));
      expect(sink.events, ['stop l2', 'start B@l1']);
      player.dispose();
    });

    test('starting mid-song begins at that position', () async {
      final audio = FakeAudio();
      final sink = RecordingSink();
      final player = SongShowPlayer(audio: audio, sink: sink, wall: () => Duration.zero);
      await player.play(show(cues: [start('a', 0, 'A'), start('b', 4, 'B')]), from: const Duration(seconds: 3));
      expect(audio.calls, ['play 3000']);
      expect(sink.events, ['start B@l1']);
      player.dispose();
    });

    test('a stop cue stops its layer and the song ending finishes the player', () async {
      final audio = FakeAudio()..length = const Duration(seconds: 2);
      final sink = RecordingSink();
      var wall = Duration.zero;
      final player = SongShowPlayer(audio: audio, sink: sink, wall: () => wall);
      var finished = false;
      player.finished.listen((_) => finished = true);
      await player.play(show(cues: [
        start('a', 0, 'A'),
        const SongCue(id: 's', atBeat: 2, layerId: 'l1', action: SongCueAction.stop),
      ]));
      for (var ms = 10; ms <= 2200; ms += 10) {
        wall = Duration(milliseconds: ms);
        audio.position = Duration(milliseconds: ms);
        player.tick();
      }
      await Future<void>.delayed(Duration.zero);
      expect(sink.events, contains('stop l1'));
      expect(finished, isTrue);
      expect(player.isPlaying, isFalse);
      player.dispose();
    });
  });
}

void projectRoundTripTests() {
  test('song shows survive a project save and load', () {
    final s = show(cues: [start('a', 0, 'A')]);
    final data = ProjectData.fromJson({
      'songShows': [s.toJson()],
    }, builtIns: const []);
    expect(data.songShows.single.toJson(), s.toJson());
    final again = ProjectData.fromJson(data.toJson(), builtIns: const []);
    expect(again.songShows.single.cues.single.target!.id, 'A');
    expect(ProjectData.fromJson({}, builtIns: const []).songShows, isEmpty);
  });
}

void audioMatchTests() {
  test('a file of nearly the same length could be the same song, a different length could not', () {
    const ref = SongAudioRef(fileName: 'a.mp3', durationMs: 200000);
    expect(ref.couldBeSameSong(200800), isTrue);
    expect(ref.couldBeSameSong(198600), isTrue);
    expect(ref.couldBeSameSong(215000), isFalse);
    expect(const SongAudioRef(fileName: 'a', durationMs: 0).couldBeSameSong(1), isTrue);
  });
}
