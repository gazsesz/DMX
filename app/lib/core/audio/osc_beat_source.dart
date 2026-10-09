import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'beat_source.dart';
import 'osc_message.dart';

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

  /// How many beat intervals the fallback tempo averages over, used only
  /// until rkbx_link has sent a tempo of its own (it only sends one when the
  /// tempo changes, so joining mid-track can mean none arrives for a while).
  static const _intervalWindow = 4;

  final int port;

  OscBeatSource({this.port = defaultPort});

  final _beatController = StreamController<DateTime>.broadcast();
  final _activityController = StreamController<DateTime>.broadcast();
  final _bpmController = StreamController<double>.broadcast();

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

  @override
  bool get isListening => _socket != null;

  @override
  Future<bool> start() async {
    if (isListening) return true;
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
      await stop();
      return false;
    }
  }

  @override
  Future<void> stop() async {
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
    for (final message in messages) {
      switch (message.address) {
        case beatAddress:
          // rkbx_link can also send a 0.0 "release" a fifth of a beat later
          // when trigger_autorelease is on — that's not a beat.
          if ((message.firstNumber ?? 1) >= 0.5) _onBeat(at);
        case bpmAddress:
          final value = message.firstNumber;
          if (value != null && value > 0) {
            _bpmFromSender = true;
            _setBpm(value);
          }
      }
    }
  }

  void _onBeat(DateTime at) {
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
    stop();
    _beatController.close();
    _activityController.close();
    _bpmController.close();
  }
}
