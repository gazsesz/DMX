import 'dart:convert';
import 'dart:typed_data';

import 'package:dmx_controller/core/audio/osc_beat_source.dart';
import 'package:dmx_controller/core/song/deck_song_audio.dart';
import 'package:dmx_controller/core/song/song_clock.dart';
import 'package:dmx_controller/core/song/song_follower.dart';
import 'package:dmx_controller/core/song/song_match.dart';
import 'package:dmx_controller/models/song_show.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _str(String s) {
  final bytes = [...utf8.encode(s), 0];
  while (bytes.length % 4 != 0) {
    bytes.add(0);
  }
  return bytes;
}

List<int> _f32(double v) => (ByteData(4)..setFloat32(0, v)).buffer.asUint8List();

Uint8List _floatMsg(String address, double value) =>
    Uint8List.fromList([..._str(address), ..._str(',f'), ..._f32(value)]);

Uint8List _stringMsg(String address, String value) =>
    Uint8List.fromList([..._str(address), ..._str(',s'), ..._str(value)]);

SongShow _show(String id, String name, {String title = '', String artist = '', String? file, bool cues = true}) =>
    SongShow(
      id: id,
      name: name,
      trackTitle: title,
      trackArtist: artist,
      audio: file == null ? null : SongAudioRef(fileName: file, durationMs: 200000),
      cues: cues ? const [SongCue(id: 'c', atBeat: 0, layerId: 'l1', action: SongCueAction.stop)] : const [],
    );

class _FakeActions implements SongFollowerActions {
  @override
  List<SongShow> shows = [];

  @override
  String? playingShowId;

  final log = <String>[];
  final reports = <Duration>[];

  @override
  Future<bool> takeOver(SongShow show, Duration from) async {
    log.add('take ${show.id} @${from.inMilliseconds}');
    playingShowId = show.id;
    return true;
  }

  @override
  void report(Duration position, double rate) => reports.add(position);

  @override
  Future<void> giveBack() async {
    log.add('giveBack');
    playingShowId = null;
  }

  @override
  void stopShow() {
    log.add('stopShow');
    playingShowId = null;
  }

  @override
  void forget() => log.add('forget');
}

void main() {
  group('OscBeatSource deck', () {
    test('reads title, artist, both time forms and tempos', () {
      final source = OscBeatSource();
      final at = DateTime(2026, 1, 1);
      source.handlePacket(_stringMsg('/master/track/title', 'One More Time'), now: at);
      source.handlePacket(_stringMsg('/master/track/artist', 'Daft Punk'), now: at);
      source.handlePacket(_floatMsg('/master/time', 12.5), now: at);
      source.handlePacket(_floatMsg('/master/bpm/current', 126), now: at);
      source.handlePacket(_floatMsg('/master/bpm/original', 120), now: at);
      expect(source.deck.title, 'One More Time');
      expect(source.deck.artist, 'Daft Punk');
      expect(source.deck.timeSec, closeTo(12.5, 1e-6));
      expect(source.deck.rate, closeTo(1.05, 1e-6));
      source.handlePacket(_floatMsg('/time/master', 20), now: at);
      expect(source.deck.timeSec, closeTo(20, 1e-6));
      expect(source.seenAddresses.map((s) => s.address), contains('/master/track/title'));
    });
  });

  group('matchSongShow', () {
    test('a paired show wins, artist optional', () {
      final shows = [
        _show('a', 'One More Time'),
        _show('b', 'Opener', title: 'One more time', artist: 'Daft Punk'),
      ];
      expect(matchSongShow(shows, title: 'One More Time', artist: 'Daft Punk')?.id, 'b');
      expect(matchSongShow(shows, title: 'One More Time')?.id, 'b');
      expect(matchSongShow(shows, title: 'One More Time', artist: 'Someone Else')?.id, 'a');
    });

    test('falls back to the show name, then the file name', () {
      final shows = [
        _show('n', 'Daft Punk - One More Time'),
        _show('f', 'My show', file: 'Pásztor – Ébredés (Extended Mix).mp3'),
      ];
      expect(matchSongShow(shows, title: 'One More Time', artist: 'Daft Punk')?.id, 'n');
      expect(matchSongShow(shows, title: 'Ebredes', artist: 'Pasztor')?.id, 'f');
      expect(matchSongShow(shows, title: 'Something else'), isNull);
    });

    test('shows without cues never match', () {
      expect(matchSongShow([_show('x', 'Track', cues: false)], title: 'Track'), isNull);
    });
  });

  group('DeckSongAudio', () {
    test('carries on at the deck rate, but only briefly, minus the offset', () {
      var wall = Duration.zero;
      final audio = DeckSongAudio(length: const Duration(minutes: 3), wall: () => wall)
        ..report(const Duration(seconds: 10), rate: 1.1);
      wall = const Duration(milliseconds: 100);
      expect(audio.position, const Duration(milliseconds: 10110));
      wall = const Duration(seconds: 2);
      expect(audio.position, const Duration(milliseconds: 10165));
      audio.offset = const Duration(milliseconds: 200);
      expect(audio.position, const Duration(milliseconds: 9965));
    });
  });

  group('SongClock stall', () {
    test('stops advancing when the position stops moving', () {
      final clock = SongClock()..start(Duration.zero, Duration.zero);
      clock.report(const Duration(milliseconds: 100), const Duration(milliseconds: 100));
      for (var ms = 110; ms <= 1000; ms += 10) {
        clock.report(const Duration(milliseconds: 100), Duration(milliseconds: ms));
      }
      final held = clock.now(const Duration(milliseconds: 1000));
      expect(held, lessThan(const Duration(milliseconds: 500)));
      // The player reports on every tick; still the same position.
      clock.report(const Duration(milliseconds: 100), const Duration(milliseconds: 3000));
      expect(clock.now(const Duration(milliseconds: 3000)), held);
    });
  });

  group('SongFollower', () {
    late _FakeActions actions;
    late SongFollower follower;
    final t0 = DateTime(2026, 1, 1, 22);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));
    RkbxDeckState deck(String title, double time) => RkbxDeckState(title: title, artist: 'DJ', timeSec: time);

    setUp(() {
      actions = _FakeActions()..shows = [_show('s1', 'Song One'), _show('s2', 'Song Two')];
      follower = SongFollower(actions);
    });

    Future<void> play(String title, double fromSec, int fromMs, int forMs) async {
      for (var ms = 0; ms <= forMs; ms += 100) {
        await follower.onDeck(deck(title, fromSec + ms / 1000), at(fromMs + ms));
      }
    }

    test('takes over once the track has played a moment, from its position', () async {
      await play('Song One', 30, 0, 300);
      expect(actions.log, isEmpty);
      await play('Song One', 30.4, 400, 200);
      expect(actions.log.single, 'take s1 @30500');
      expect(follower.status.phase, SongWatchPhase.following);
      expect(actions.reports.last, const Duration(milliseconds: 30600));
    });

    test('a track without a show leaves the program alone', () async {
      await play('Unknown', 0, 0, 2000);
      expect(actions.log, isEmpty);
    });

    test('a paused deck gives the stage back, playing on takes it again', () async {
      await play('Song One', 0, 0, 1000);
      await follower.onTick(at(2000));
      expect(actions.log.last, startsWith('take'));
      await follower.onTick(at(4000));
      expect(actions.log.last, 'giveBack');
      await play('Song One', 1.1, 5000, 600);
      expect(actions.log.last, startsWith('take s1'));
    });

    test('the next track with a show switches straight over', () async {
      await play('Song One', 0, 0, 1000);
      await play('Song Two', 0, 1100, 1000);
      expect(actions.log, ['take s1 @500', 'stopShow', 'take s2 @500']);
    });

    test('the next track without a show brings the program back', () async {
      await play('Song One', 0, 0, 1000);
      await play('Unknown', 0, 1100, 500);
      expect(actions.log, ['take s1 @500', 'giveBack']);
    });

    test('a show that ends gives back and does not restart on the same track', () async {
      await play('Song One', 0, 0, 1000);
      actions.playingShowId = null; // the show reached its end
      await follower.onTick(at(1100));
      expect(actions.log.last, 'giveBack');
      await play('Song One', 1.2, 1200, 2000);
      expect(actions.log.where((l) => l.startsWith('take')), hasLength(1));
    });

    test('something started by hand is left alone', () async {
      await play('Song One', 0, 0, 1000);
      actions.playingShowId = 'other';
      await follower.onTick(at(1100));
      expect(actions.log.last, 'forget');
      await play('Song One', 1.2, 1200, 1000);
      expect(actions.log.where((l) => l.startsWith('take')), hasLength(1));
    });
  });

  group('SongShow track pairing json', () {
    test('round-trips and stays out of old files', () {
      final show = _show('a', 'A', title: 'T', artist: 'X');
      final back = SongShow.fromJson(show.toJson());
      expect(back.trackTitle, 'T');
      expect(back.trackArtist, 'X');
      expect(_show('b', 'B').toJson().containsKey('trackTitle'), isFalse);
    });
  });
}
