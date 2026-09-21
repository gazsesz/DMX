import 'dart:async';

import 'package:flutter_midi_command/flutter_midi_command.dart';

import 'beat_source.dart';
import 'midi_clock_counter.dart';

/// A [BeatSource] driven by an incoming MIDI clock over USB, instead of the
/// microphone guessing from audio. Once connected to a device that's
/// actually sending clock (0xF8, 24 pulses per quarter note — see
/// [MidiClockCounter]), the beat is exact rather than estimated: no
/// threshold, no missed onset, and 0xFA (Start) gives a real downbeat.
///
/// Device selection is separate from listening: [availableDevices] and
/// [connect] let Setup show a picker and remember the choice, while
/// [start]/[stop] (the [BeatSource] contract every player uses) just
/// (re)connect to whatever [connect] last picked.
class MidiBeatSource implements BeatSource {
  final MidiCommand _midi = MidiCommand();
  final _beatController = StreamController<DateTime>.broadcast();
  final _activityController = StreamController<DateTime>.broadcast();
  final _bpmController = StreamController<double>.broadcast();
  final _clock = MidiClockCounter();

  StreamSubscription<MidiPacket>? _sub;
  MidiDevice? _device;

  /// How many beats' worth of clock pulses [_pulseTimes] keeps — averaging
  /// over just one beat still let a single mistimed pulse (USB/platform
  /// - channel jitter, not the DAW's fault) swing the reading a few BPM
  /// between updates. Four beats' worth of pulses averages that out to
  /// something steady while still catching a real tempo change within a
  /// couple of seconds.
  static const _pulseWindowBeats = 4;
  static const _pulseWindowCapacity = _pulseWindowBeats * MidiClockCounter.pulsesPerBeat + 1;

  /// The last [_pulseWindowCapacity] clock-byte timestamps, oldest first.
  final _pulseTimes = <DateTime>[];

  @override
  String? lastError;

  /// The tempo the incoming clock is actually running at right now — exact,
  /// since it comes straight from pulse timing rather than [beatEvents]'
  /// onset-style guessing. Null until enough pulses have arrived to average.
  double? lastBpm;

  /// Fires whenever [lastBpm] updates.
  Stream<double> get bpm => _bpmController.stream;

  @override
  Stream<DateTime> get beatEvents => _beatController.stream;

  /// Fires on *every* incoming MIDI byte, clock or not — lets the UI tell
  /// "nothing is arriving at all" (a cabling/routing problem) apart from
  /// "bytes are arriving but none of them are clock" (Sync isn't enabled on
  /// the DAW's output, or it's sending something other than clock).
  Stream<DateTime> get activity => _activityController.stream;

  @override
  bool get isListening => _sub != null;

  /// The device [connect] last connected to, whether or not it's still
  /// listening — Setup shows this even after a disconnect so "which one"
  /// stays visible while reconnecting.
  MidiDevice? get connectedDevice => _device;

  /// When *any* byte last arrived from the connected device — clock or not.
  /// Separate from a beat firing so Setup/the dock can tell "nothing is
  /// coming down the wire at all" (a routing problem) apart from "bytes are
  /// arriving but none of them are clock" (Sync isn't enabled on the DAW's
  /// output, or it's sending something else, like note data from a pad).
  DateTime? lastMessageAt;

  /// USB (and any other transport the platform exposes) MIDI devices
  /// currently visible to Android — empty until something is plugged in and
  /// enumerated.
  Future<List<MidiDevice>> availableDevices() async {
    try {
      return await _midi.devices ?? const [];
    } catch (e) {
      lastError = 'Could not list MIDI devices: $e';
      return const [];
    }
  }

  /// Connects to [device] and starts listening for its clock. Returns false
  /// if the connection failed — check [lastError] for why. Remembers
  /// [device] either way, so Setup can show what was picked and offer retry.
  Future<bool> connect(MidiDevice device) async {
    await stop();
    // Disconnect whatever this source connected to before, so switching
    // devices in Setup doesn't leave the old one connected at the native
    // level — otherwise it keeps showing as "connected" (and holding the
    // port open) even though nothing here is listening to it any more.
    final previous = _device;
    if (previous != null && previous.id != device.id) {
      _midi.disconnectDevice(previous);
    }
    lastError = null;
    lastMessageAt = null;
    _device = device;
    try {
      await _midi.connectToDevice(device);
    } catch (e) {
      lastError = 'Could not connect to ${device.name}: $e';
      return false;
    }
    final packets = _midi.onMidiPacketReceived;
    if (packets == null) {
      lastError = 'No MIDI input on this platform';
      return false;
    }
    _clock.reset();
    _pulseTimes.clear();
    lastBpm = null;
    _sub = packets.where((p) => p.device.id == device.id).listen(_onPacket);
    return true;
  }

  void disconnect() {
    _sub?.cancel();
    _sub = null;
    final device = _device;
    if (device != null) _midi.disconnectDevice(device);
  }

  /// Reconnects to whatever [connect] last picked — the [BeatSource]
  /// contract every player calls, e.g. via the dock's Beat toggle or a
  /// chase's own beat sync.
  @override
  Future<bool> start() async {
    if (isListening) return true;
    final device = _device;
    if (device == null) {
      lastError = 'No MIDI device selected — pick one in Setup';
      return false;
    }
    return connect(device);
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  void _onPacket(MidiPacket packet) {
    final data = packet.data;
    if (data.isEmpty) return;
    lastMessageAt = DateTime.now();
    _activityController.add(lastMessageAt!);
    final status = data[0];
    if (status == MidiClockCounter.clockByte) {
      _pulseTimes.add(lastMessageAt!);
      if (_pulseTimes.length > _pulseWindowCapacity) _pulseTimes.removeAt(0);
    } else if (status == MidiClockCounter.startByte || status == MidiClockCounter.continueByte) {
      // A restarted transport's pulses aren't evenly spaced with whatever
      // came before it — averaging across the seam would report a bogus
      // tempo for the next beat, so start the window over.
      _pulseTimes.clear();
    }
    // Only recomputed on a completed beat, not per pulse (24x/beat) — the
    // number only needs to move about as often as a beat does, and this
    // gives every update the full window to average over.
    if (_clock.feed(status)) {
      _beatController.add(DateTime.now());
      _updateBpm();
    }
  }

  /// Reports the tempo implied by however much of the pulse window has
  /// filled so far — anywhere from one beat up to [_pulseWindowBeats].
  void _updateBpm() {
    if (_pulseTimes.length < MidiClockCounter.pulsesPerBeat + 1) return;
    final spanMs = _pulseTimes.last.difference(_pulseTimes.first).inMicroseconds / 1000;
    if (spanMs <= 0) return;
    final beatsInWindow = (_pulseTimes.length - 1) / MidiClockCounter.pulsesPerBeat;
    lastBpm = beatsInWindow * 60000 / spanMs;
    _bpmController.add(lastBpm!);
  }

  void dispose() {
    _sub?.cancel();
    _beatController.close();
    _activityController.close();
    _bpmController.close();
  }
}
