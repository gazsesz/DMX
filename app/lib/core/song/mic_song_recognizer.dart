import 'dart:typed_data';

import 'fingerprint.dart';

/// Listens to the room through the microphone and tells which known song is
/// playing and where it is in it, from the [FingerprintIndex] of the song
/// shows' audio files.
///
/// The last [clipSeconds] of sound are kept; every query looks for them in
/// the index. One match is only a candidate — a second one that agrees (same
/// song, position moved on by the time that passed) confirms it, so a chance
/// match in a noisy room doesn't take the stage. Once confirmed, every
/// agreeing match keeps it alive and pulls the position back in line; after
/// [lostAfter] without one, the song counts as gone.
class MicSongRecognizer {
  static const clipSeconds = 7;

  /// A song not heard again for this long has stopped or been mixed out.
  static const lostAfter = Duration(seconds: 12);

  /// How far a new match may sit from the predicted position and still count
  /// as the same playback.
  static const agreeWithin = 0.4;

  MicSongRecognizer({required this.index, required this.songIds});

  final FingerprintIndex index;

  /// The id for each song in [index], in index order.
  final List<String> songIds;

  final _ring = Float32List(clipSeconds * fingerprintSampleRate);
  int _write = 0;
  int _filled = 0;
  DateTime? _lastSampleAt;
  final _leftover = <int>[];

  String? _candidateId;
  double _candidatePos = 0;
  DateTime? _candidateAt;

  String? _songId;
  double _basePos = 0;
  DateTime? _baseAt;
  DateTime? _confirmedAt;

  /// The last match found, for Setup's status line.
  FingerprintMatch? lastMatch;

  /// Feeds one chunk of microphone PCM (16-bit little-endian at 44.1 kHz)
  /// received at [at].
  void addPcm(Uint8List chunk, DateTime at) {
    // Keep a whole number of 4-sample groups; carry the rest over.
    final bytes = _leftover.isEmpty ? chunk : Uint8List.fromList([..._leftover, ...chunk]);
    final usable = bytes.length - bytes.length % 8;
    _leftover
      ..clear()
      ..addAll(bytes.sublist(usable));
    final samples = downsampleMicPcm(Uint8List.sublistView(bytes, 0, usable));
    for (final s in samples) {
      _ring[_write] = s;
      _write = (_write + 1) % _ring.length;
      if (_filled < _ring.length) _filled++;
    }
    _lastSampleAt = at;
  }

  /// Feeds samples already at [fingerprintSampleRate] (tests).
  void addSamples(Float32List samples, DateTime at) {
    for (final s in samples) {
      _ring[_write] = s;
      _write = (_write + 1) % _ring.length;
      if (_filled < _ring.length) _filled++;
    }
    _lastSampleAt = at;
  }

  /// The recognised song, if one is confirmed and still heard.
  String? songAt(DateTime now) {
    final at = _confirmedAt;
    if (_songId == null || at == null || now.difference(at) > lostAfter) return null;
    return _songId;
  }

  /// Where the recognised song is at [now], in seconds.
  double positionAt(DateTime now) =>
      _basePos + (_baseAt == null ? 0 : now.difference(_baseAt!).inMicroseconds / 1e6);

  /// Looks for the last few seconds in the index. Call every couple of
  /// seconds.
  void query(DateTime now) {
    final end = _lastSampleAt;
    if (end == null || _filled < _ring.length) return;
    final clip = Float32List(_ring.length);
    for (var i = 0; i < clip.length; i++) {
      clip[i] = _ring[(_write + i) % _ring.length];
    }
    final match = index.query(clip);
    lastMatch = match;
    if (match == null || match.song >= songIds.length) return;
    final id = songIds[match.song];
    // The match is the clip's start; the clip ended at the last sample.
    final pos = match.offsetSec + clipSeconds + now.difference(end).inMicroseconds / 1e6;

    if (songAt(now) == id && (positionAt(now) - pos).abs() < agreeWithin * 3) {
      _confirmedAt = now;
      // Small differences are measurement noise; follow only real drift.
      if ((positionAt(now) - pos).abs() > 0.12) _setBase(pos, now);
      return;
    }
    final predicted = _candidateAt == null ? null : _candidatePos + now.difference(_candidateAt!).inMicroseconds / 1e6;
    if (_candidateId == id && predicted != null && (predicted - pos).abs() < agreeWithin) {
      _songId = id;
      _setBase(pos, now);
      _confirmedAt = now;
      _candidateId = null;
      return;
    }
    _candidateId = id;
    _candidatePos = pos;
    _candidateAt = now;
  }

  void _setBase(double pos, DateTime now) {
    _basePos = pos;
    _baseAt = now;
  }
}
