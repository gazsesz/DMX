import 'dart:async';

import 'package:record/record.dart';

/// One live audio-level reading, for driving a VU meter / LED indicator.
class BeatMeterSample {
  final double db; // current level, dBFS (roughly -160 silent .. 0 max)
  final double avg; // rolling ambient average, same units
  final double threshold; // level a beat needs to cross right now
  final double requiredRise; // threshold - avg, i.e. how sensitive we are
  final bool isBeat;

  const BeatMeterSample({
    required this.db,
    required this.avg,
    required this.threshold,
    required this.requiredRise,
    required this.isBeat,
  });
}

/// Simple energy-based beat/onset detector: watches the microphone's dBFS
/// amplitude and fires an event whenever it spikes well above its own
/// recent rolling average — a lightweight stand-in for real beat tracking,
/// good enough to nudge a chase or the tap-tempo display in time with music.
class BeatDetectorService {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _amplitudeSub;
  final _beatController = StreamController<DateTime>.broadcast();
  final _meterController = StreamController<BeatMeterSample>.broadcast();
  final List<double> _recentDb = [];
  DateTime? _lastBeat;

  /// 0 (least sensitive, needs a big spike) .. 1 (most sensitive).
  double sensitivity = 0.6;

  /// Set when [start] fails, so the UI can show *why* instead of just "no".
  String? lastError;

  Stream<DateTime> get beatEvents => _beatController.stream;
  Stream<BeatMeterSample> get meterStream => _meterController.stream;
  bool get isListening => _amplitudeSub != null;

  /// Starts listening. Returns false if permission was denied or the
  /// platform couldn't open a capture device — check [lastError] for why.
  Future<bool> start() async {
    if (isListening) return true;
    lastError = null;
    try {
      final granted = await _recorder.hasPermission();
      if (!granted) {
        lastError = 'Microphone permission denied';
        return false;
      }

      final devices = await _recorder.listInputDevices();
      if (devices.isEmpty) {
        lastError = 'No microphone/input device found';
        return false;
      }

      await _recorder.startStream(const RecordConfig(encoder: AudioEncoder.pcm16bits, numChannels: 1));
      _recentDb.clear();
      _lastBeat = null;
      _amplitudeSub = _recorder.onAmplitudeChanged(const Duration(milliseconds: 30)).listen(_onAmplitude);
      return true;
    } catch (e) {
      lastError = e.toString();
      await _safeStop();
      return false;
    }
  }

  Future<void> stop() async {
    await _safeStop();
  }

  Future<void> _safeStop() async {
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    try {
      await _recorder.stop();
    } catch (_) {
      // Already stopped/never started — nothing to clean up.
    }
  }

  void _onAmplitude(Amplitude amplitude) {
    final db = amplitude.current.isFinite ? amplitude.current : -160.0;
    _recentDb.add(db);
    if (_recentDb.length > 40) _recentDb.removeAt(0);
    // Higher sensitivity -> a smaller dB rise is enough to count as a beat.
    // Wide range (2..26dB) so low sensitivity stays quiet even against loud,
    // steady music instead of triggering on every small fluctuation.
    // Computed even during warm-up so the UI reflects the slider right away.
    final requiredRise = 26 - sensitivity * 24;

    if (_recentDb.length < 8) {
      // Rolling average still warming up — show the raw level, no beats yet.
      _meterController.add(
        BeatMeterSample(db: db, avg: db, threshold: db + requiredRise, requiredRise: requiredRise, isBeat: false),
      );
      return;
    }

    final avg = _recentDb.reduce((a, b) => a + b) / _recentDb.length;
    final threshold = avg + requiredRise;
    final now = DateTime.now();
    final pastRefractoryPeriod =
        _lastBeat == null || now.difference(_lastBeat!) > const Duration(milliseconds: 250);

    final isBeat = db > threshold && db > -50 && pastRefractoryPeriod;
    if (isBeat) {
      _lastBeat = now;
      _beatController.add(now);
    }
    _meterController.add(
      BeatMeterSample(db: db, avg: avg, threshold: threshold, requiredRise: requiredRise, isBeat: isBeat),
    );
  }

  void dispose() {
    _amplitudeSub?.cancel();
    _recorder.dispose();
    _beatController.close();
    _meterController.close();
  }
}
