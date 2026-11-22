import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dmx_controller/core/song/fingerprint.dart';
import 'package:dmx_controller/core/song/mic_song_recognizer.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List _song(int seed, double seconds) {
  final rnd = math.Random(seed);
  final n = (seconds * fingerprintSampleRate).round();
  final out = Float32List(n);
  var i = 0;
  while (i < n) {
    final len = ((0.15 + rnd.nextDouble() * 0.25) * fingerprintSampleRate).round();
    final f1 = 150 + rnd.nextDouble() * 1500;
    final f2 = 300 + rnd.nextDouble() * 3000;
    for (var k = 0; k < len && i < n; k++, i++) {
      final t = i / fingerprintSampleRate;
      out[i] = 0.4 * math.sin(2 * math.pi * f1 * t) + 0.25 * math.sin(2 * math.pi * f2 * t) + 0.05 * (rnd.nextDouble() - 0.5);
    }
  }
  return out;
}

void main() {
  final songs = [_song(1, 90), _song(2, 90)];
  final index = FingerprintIndex.fromSamples(songs);
  final t0 = DateTime(2026, 1, 1, 22);

  /// "Plays" [song] into the recognizer from [fromSec], in 0.5 s chunks, for
  /// [seconds], querying every 2 s. Returns the time reached.
  DateTime play(MicSongRecognizer rec, Float32List song, double fromSec, double seconds, DateTime start) {
    const chunk = 0.5;
    var now = start;
    for (var t = 0.0; t < seconds; t += chunk) {
      final from = ((fromSec + t) * fingerprintSampleRate).round();
      final n = (chunk * fingerprintSampleRate).round();
      // The chunk's last sample arrives at the end of its half second.
      now = now.add(const Duration(milliseconds: 500));
      rec.addSamples(Float32List.sublistView(song, from, from + n), now);
      if ((t / chunk).round() % 4 == 3) rec.query(now);
    }
    return now;
  }

  test('confirms a song after two agreeing matches, with its position', () {
    final rec = MicSongRecognizer(index: index, songIds: ['a', 'b']);
    var now = play(rec, songs[1], 20, 8, t0);
    expect(rec.songAt(now), isNull, reason: 'one match is only a candidate');
    now = play(rec, songs[1], 28, 4, now);
    expect(rec.songAt(now), 'b');
    expect(rec.positionAt(now), closeTo(32, 0.25));
  });

  test('forgets a song that is no longer heard', () {
    final rec = MicSongRecognizer(index: index, songIds: ['a', 'b']);
    final now = play(rec, songs[0], 10, 14, t0);
    expect(rec.songAt(now), 'a');
    expect(rec.songAt(now.add(const Duration(seconds: 13))), isNull);
  });

  test('switches to the next song once it is confirmed', () {
    final rec = MicSongRecognizer(index: index, songIds: ['a', 'b']);
    var now = play(rec, songs[0], 10, 12, t0);
    expect(rec.songAt(now), 'a');
    now = play(rec, songs[1], 40, 14, now);
    expect(rec.songAt(now), 'b');
    expect(rec.positionAt(now), closeTo(54, 0.25));
  });
}
