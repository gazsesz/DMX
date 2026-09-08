import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

/// Which part of the audio spectrum the detector reacts to — lets a kick
/// drum (bass), snare/vocals (mid), or hi-hats/cymbals (high) drive the
/// sync instead of only overall loudness.
enum BeatFrequencyBand {
  overall,
  kick,
  bass,
  mid,
  high;

  String get label => switch (this) {
    BeatFrequencyBand.overall => 'Volume',
    BeatFrequencyBand.kick => 'Kick/Drum',
    BeatFrequencyBand.bass => 'Bass',
    BeatFrequencyBand.mid => 'Mid',
    BeatFrequencyBand.high => 'High',
  };
}

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

/// A one-pole IIR low-pass filter — cheap, stable, and enough to split raw
/// PCM into bass/mid/high energy without pulling in a full FFT.
class _LowPassFilter {
  double _y = 0;
  final double _alpha;

  _LowPassFilter(double cutoffHz, double sampleRate)
    : _alpha = (1 / sampleRate) / ((1 / (2 * math.pi * cutoffHz)) + (1 / sampleRate));

  double process(double x) {
    _y += _alpha * (x - _y);
    return _y;
  }
}

/// Simple energy-based beat/onset detector: watches the microphone's dBFS
/// amplitude (optionally restricted to a bass/mid/high band) and fires an
/// event whenever it spikes well above its own recent rolling average — a
/// lightweight stand-in for real beat tracking, good enough to nudge a
/// chase or the tap-tempo display in time with music.
class BeatDetectorService {
  static const _sampleRate = 44100.0;
  // Kick drums live mostly in a narrow ~40-150Hz pocket; "Bass" is the
  // wider, more general low end (bassline notes, sub content, etc).
  static const _kickLowCutoffHz = 40.0;
  static const _kickHighCutoffHz = 150.0;
  static const _bassCutoffHz = 250.0;
  static const _midCutoffHz = 2000.0;
  static const _samplesPerTick = 1323; // ~30ms at 44.1kHz

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _pcmSub;
  final _beatController = StreamController<DateTime>.broadcast();
  final _meterController = StreamController<BeatMeterSample>.broadcast();
  final List<double> _recentDb = [];
  DateTime? _lastBeat;

  _LowPassFilter? _kickLowFilter;
  _LowPassFilter? _kickHighFilter;
  _LowPassFilter? _bassFilter;
  _LowPassFilter? _midHighFilter;
  double _sumSquares = 0;
  int _sampleCount = 0;

  /// 0 (least sensitive, needs a big spike) .. 1 (most sensitive).
  double sensitivity = 0.6;

  /// Which frequency band [sensitivity]/detection reacts to.
  BeatFrequencyBand frequencyBand = BeatFrequencyBand.overall;

  /// Set when [start] fails, so the UI can show *why* instead of just "no".
  String? lastError;

  Stream<DateTime> get beatEvents => _beatController.stream;
  Stream<BeatMeterSample> get meterStream => _meterController.stream;
  bool get isListening => _pcmSub != null;

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

      final stream = await _recorder.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, numChannels: 1, sampleRate: 44100),
      );
      _recentDb.clear();
      _lastBeat = null;
      _sumSquares = 0;
      _sampleCount = 0;
      _kickLowFilter = _LowPassFilter(_kickLowCutoffHz, _sampleRate);
      _kickHighFilter = _LowPassFilter(_kickHighCutoffHz, _sampleRate);
      _bassFilter = _LowPassFilter(_bassCutoffHz, _sampleRate);
      _midHighFilter = _LowPassFilter(_midCutoffHz, _sampleRate);
      _pcmSub = stream.listen(_onPcmChunk);
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
    await _pcmSub?.cancel();
    _pcmSub = null;
    try {
      await _recorder.stop();
    } catch (_) {
      // Already stopped/never started — nothing to clean up.
    }
  }

  void _onPcmChunk(Uint8List chunk) {
    final kickLowFilter = _kickLowFilter;
    final kickHighFilter = _kickHighFilter;
    final bassFilter = _bassFilter;
    final midHighFilter = _midHighFilter;
    if (kickLowFilter == null || kickHighFilter == null || bassFilter == null || midHighFilter == null) {
      return;
    }
    final byteData = ByteData.sublistView(chunk);
    for (var i = 0; i + 1 < chunk.length; i += 2) {
      final sample = byteData.getInt16(i, Endian.little) / 32768.0;
      final kickLow = kickLowFilter.process(sample);
      final kickHigh = kickHighFilter.process(sample);
      final bass = bassFilter.process(sample);
      final midHigh = midHighFilter.process(sample);
      final double bandValue;
      switch (frequencyBand) {
        case BeatFrequencyBand.kick:
          bandValue = kickHigh - kickLow;
          break;
        case BeatFrequencyBand.bass:
          bandValue = bass;
          break;
        case BeatFrequencyBand.mid:
          bandValue = midHigh - bass;
          break;
        case BeatFrequencyBand.high:
          bandValue = sample - midHigh;
          break;
        case BeatFrequencyBand.overall:
          bandValue = sample;
          break;
      }
      _sumSquares += bandValue * bandValue;
      _sampleCount++;
      if (_sampleCount >= _samplesPerTick) {
        final rms = math.sqrt(_sumSquares / _sampleCount);
        final db = rms > 0 ? (20 * math.log(rms) / math.ln10).clamp(-160.0, 0.0) : -160.0;
        _sumSquares = 0;
        _sampleCount = 0;
        _handleDbSample(db);
      }
    }
  }

  void _handleDbSample(double db) {
    _recentDb.add(db);
    // ~2.7s window (90 samples @ ~30ms). A short window lets the "ambient
    // average" chase the music's own loud passages almost in real time, so
    // genuine beats never sit far enough above it to be filtered out — a
    // longer, steadier baseline is what actually makes the sensitivity
    // threshold mean something during continuously loud music.
    if (_recentDb.length > 90) _recentDb.removeAt(0);
    // Higher sensitivity -> a smaller dB rise is enough to count as a beat.
    // Wide range (2..26dB) so low sensitivity stays quiet even against loud,
    // steady music instead of triggering on every small fluctuation.
    // Computed even during warm-up so the UI reflects the slider right away.
    final requiredRise = 26 - sensitivity * 24;

    if (_recentDb.length < 20) {
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
    _pcmSub?.cancel();
    _recorder.dispose();
    _beatController.close();
    _meterController.close();
  }
}
