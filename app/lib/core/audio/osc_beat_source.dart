import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'beat_source.dart';
import 'osc_message.dart';

/// What rkbx_link last said about Rekordbox's master deck: which track is on
/// it and where it is in that track. Feeds Song watch, which follows a
/// [SongShow] along with the DJ's own playback.
class RkbxDeckState {
  final String? title;
  final String? artist;

  /// Position in the track, in seconds, as of [timeAt].
  final double? timeSec;
  final DateTime? timeAt;

  /// The pitched tempo and the track's own tempo — their ratio is how fast
  /// the track runs, so the position can be carried on between reports.
  final double? bpm;
  final double? originalBpm;

  const RkbxDeckState({this.title, this.artist, this.timeSec, this.timeAt, this.bpm, this.originalBpm});

  /// Playback speed relative to the original track (1.0 when unknown).
  double get rate {
    final b = bpm, o = originalBpm;
    if (b == null || o == null || b <= 0 || o <= 0) return 1;
    final r = b / o;
    return r < 0.5 || r > 2 ? 1 : r;
  }

  bool get hasTrack => (title ?? '').trim().isNotEmpty;

  RkbxDeckState copyWith({
    String? title,
    String? artist,
    double? timeSec,
    DateTime? timeAt,
    double? bpm,
    double? originalBpm,
  }) => RkbxDeckState(
    title: title ?? this.title,
    artist: artist ?? this.artist,
    timeSec: timeSec ?? this.timeSec,
    timeAt: timeAt ?? this.timeAt,
    bpm: bpm ?? this.bpm,
    originalBpm: originalBpm ?? this.originalBpm,
  );
}

/// One OSC address seen from rkbx_link, for Setup's monitor.
class OscSeen {
  final String address;
  final String lastValue;
  final int count;
  final DateTime lastAt;

  const OscSeen(this.address, this.lastValue, this.count, this.lastAt);
}

/// A [BeatSource] fed by rkbx_link's OSC output over Wi-Fi: rkbx_link reads
/// Rekordbox's master deck (tempo and beatgrid position) straight from
/// memory and sends a trigger on every beat, so the beat lands on the
/// track's own grid — no microphone guessing, no Ableton or USB cable in
/// between.
///
/// What it listens for (rkbx_link's addresses, see its README):
/// - [beatAddress] — `/master/beat/trigger/1`, value 1.0 once per beat
///   (enabled with `osc.msg.master/beat/trigger 1` in rkbx_link's config).
/// - [bpmAddress] — `/master/bpm/current`, the master deck's pitched tempo,
///   sent whenever it changes.
///
/// Everything else rkbx_link sends (phrases, track titles, subdivisions)
/// still counts as [activity], so Setup can tell "nothing arrives at all" (a
/// network/IP problem) apart from "data arrives but no beats" (the trigger
/// line is missing from rkbx_link's config, or the deck isn't playing).
class OscBeatSource implements BeatSource {
  /// rkbx_link's default `osc.destination` port, so the only thing to change
  /// on the PC side is the IP address.
  static const defaultPort = 4460;
  static const beatAddress = '/master/beat/trigger/1';
  static const bpmAddress = '/master/bpm/current';
  static const originalBpmAddress = '/master/bpm/original';

  /// The master deck's position in seconds. rkbx_link's README names both
  /// forms, so both are accepted.
  static const timeAddresses = {'/master/time', '/time/master'};
  static const titleAddress = '/master/track/title';
  static const artistAddress = '/master/track/artist';

  /// Who holds the socket open: the beat sync switch and Song watch can each
  /// keep it listening without the other turning it off.
  static const beatHolder = 'beat';
  static const songWatchHolder = 'songWatch';

  /// How many distinct addresses the monitor keeps.
  static const _maxSeen = 40;

  /// How many beat intervals the fallback tempo averages over, used only
  /// until rkbx_link has sent a tempo of its own (it only sends one when the
  /// tempo changes, so joining mid-track can mean none arrives for a while).
  static const _intervalWindow = 4;

  final int port;

  OscBeatSource({this.port = defaultPort});

  final _beatController = StreamController<DateTime>.broadcast();
  final _activityController = StreamController<DateTime>.broadcast();
  final _bpmController = StreamController<double>.broadcast();
  final _deckController = StreamController<RkbxDeckState>.broadcast();
  final _holders = <String>{};
  final _seen = <String, OscSeen>{};

  /// The master deck as rkbx_link last described it.
  RkbxDeckState deck = const RkbxDeckState();

  /// Every update to [deck]: a new position, track or tempo.
  Stream<RkbxDeckState> get deckUpdates => _deckController.stream;

  /// The addresses that have arrived, most recent first — Setup shows them
  /// so the rkbx_link config can be checked without a PC-side tool.
  List<OscSeen> get seenAddresses => _seen.values.toList()..sort((a, b) => b.lastAt.compareTo(a.lastAt));

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _sub;
  final _beatTimes = <DateTime>[];
  bool _bpmFromSender = false;

  @override
  String? lastError;

  /// The master deck's tempo — rkbx_link's own figure once it has sent one,
  /// otherwise estimated from the spacing of the beat triggers.
  double? lastBpm;

  /// When any OSC packet last arrived, beat or not.
  DateTime? lastMessageAt;

  /// The address rkbx_link's packets last came from, so Setup can show which
  /// PC is sending.
  InternetAddress? lastSender;

  Stream<double> get bpm => _bpmController.stream;

  /// Fires on every OSC message, beat or not.
  Stream<DateTime> get activity => _activityController.stream;

  @override
  Stream<DateTime> get beatEvents => _beatController.stream;

  /// Whether beats are being delivered — the socket is open for the beat
  /// sync switch. Song watch alone keeps the socket open without turning
  /// beats on for playback.
  @override
  bool get isListening => _socket != null && _holders.contains(beatHolder);

  /// Whether the socket is open for anyone.
  bool get isOpen => _socket != null;

  @override
  Future<bool> start() => open(beatHolder);

  @override
  Future<void> stop() => release(beatHolder);

  /// Opens the socket on [holder]'s behalf (or joins it if it's open).
  Future<bool> open(String holder) async {
    if (_socket == null && !await _bind()) return false;
    _holders.add(holder);
    return true;
  }

  /// Lets go on [holder]'s behalf; the socket closes when nobody holds it.
  Future<void> release(String holder) async {
    _holders.remove(holder);
    if (_holders.isEmpty) await _close();
  }

  /// Closes and binds the socket again for the same holders — after a Wi-Fi
  /// change, when the old socket may be tied to the previous network.
  Future<void> rebind() async {
    if (_socket == null) return;
    await _close();
    if (!await _bind()) _holders.clear();
  }

  Future<bool> _bind() async {
    lastError = null;
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true);
      _socket = socket;
      _sub = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = socket.receive()) != null) {
          lastSender = datagram!.address;
          handlePacket(datagram.data);
        }
      });
      return true;
    } catch (e) {
      lastError = 'Could not listen on UDP port $port: $e';
      await _close();
      return false;
    }
  }

  Future<void> _close() async {
    await _sub?.cancel();
    _sub = null;
    _socket?.close();
    _socket = null;
  }

  /// Feeds one received datagram in. Public so tests can drive the source
  /// without a socket.
  void handlePacket(Uint8List bytes, {DateTime? now}) {
    final messages = decodeOscPacket(bytes);
    if (messages.isEmpty) return;
    final at = now ?? DateTime.now();
    lastMessageAt = at;
    _activityController.add(at);
    var deck = this.deck;
    for (final message in messages) {
      _remember(message, at);
      final address = message.address;
      switch (address) {
        case beatAddress:
          // rkbx_link can also send a 0.0 "release" a fifth of a beat later
          // when trigger_autorelease is on — that's not a beat.
          if ((message.firstNumber ?? 1) >= 0.5) _onBeat(at);
        case bpmAddress:
          final value = message.firstNumber;
          if (value != null && value > 0) {
            _bpmFromSender = true;
            _setBpm(value);
            deck = deck.copyWith(bpm: value);
          }
        case originalBpmAddress:
          final value = message.firstNumber;
          if (value != null && value > 0) deck = deck.copyWith(originalBpm: value);
        case titleAddress:
          final value = _text(message);
          if (value != null) deck = deck.copyWith(title: value);
        case artistAddress:
          final value = _text(message);
          if (value != null) deck = deck.copyWith(artist: value);
        default:
          if (timeAddresses.contains(address)) {
            final value = message.firstNumber;
            if (value != null && value >= 0) deck = deck.copyWith(timeSec: value, timeAt: at);
          }
      }
    }
    if (!identical(deck, this.deck)) {
      this.deck = deck;
      _deckController.add(deck);
    }
  }

  static String? _text(OscMessage message) {
    if (message.args.isEmpty) return '';
    final value = message.args.first;
    return value is String ? value : value?.toString();
  }

  void _remember(OscMessage message, DateTime at) {
    final value = message.args.map((a) => a is double ? a.toStringAsFixed(3) : '$a').join(' ');
    final previous = _seen[message.address];
    if (previous == null && _seen.length >= _maxSeen) return;
    _seen[message.address] = OscSeen(message.address, value, (previous?.count ?? 0) + 1, at);
  }

  void _onBeat(DateTime at) {
    // Open only for Song watch: the beat sync switch is off, so playback
    // gets no beats, the same as the microphone when it isn't listening.
    if (_socket != null && !_holders.contains(beatHolder)) return;
    _beatController.add(at);
    _beatTimes.add(at);
    if (_beatTimes.length > _intervalWindow + 1) _beatTimes.removeAt(0);
    if (_bpmFromSender || _beatTimes.length < 2) return;
    final spanMs = _beatTimes.last.difference(_beatTimes.first).inMicroseconds / 1000;
    if (spanMs <= 0) return;
    final estimate = (_beatTimes.length - 1) * 60000 / spanMs;
    // A paused deck followed by play leaves one huge gap in the window —
    // a reading that far out is that gap, not the tempo, so start over.
    if (estimate < 40 || estimate > 250) {
      _beatTimes
        ..clear()
        ..add(at);
      return;
    }
    _setBpm(estimate);
  }

  void _setBpm(double value) {
    lastBpm = value;
    _bpmController.add(value);
  }

  void dispose() {
    _holders.clear();
    _close();
    _deckController.close();
    _beatController.close();
    _activityController.close();
    _bpmController.close();
  }
}
