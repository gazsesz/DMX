import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';
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

/// One band's onset level against its own recent norm, for a VU bar.
class BandLevel {
  final double db; // this band's onset strength right now, dB-like
  final double avg; // its own rolling average, same units

  const BandLevel({required this.db, required this.avg});
}

/// One live audio-level reading, for driving a VU meter / LED indicator.
class BeatMeterSample {
  final double db; // current onset-strength level, dB-like scale
  final double avg; // rolling ambient average, same units
  final double threshold; // level a beat needs to cross right now
  final double requiredRise; // threshold - avg, i.e. how sensitive we are
  final bool isBeat;

  /// The band detection is currently listening to.
  final BeatFrequencyBand band;

  /// Every band's level, whether or not it's the one being watched — so the
  /// meter can show all of them at once and you can see which band the beat
  /// actually lives in before committing to it.
  final Map<BeatFrequencyBand, BandLevel> bands;

  const BeatMeterSample({
    required this.db,
    required this.avg,
    required this.threshold,
    required this.requiredRise,
    required this.isBeat,
    this.band = BeatFrequencyBand.overall,
    this.bands = const {},
  });
}

/// Spectral-flux onset/beat detector: runs a windowed FFT over the
/// microphone's raw PCM at a steady hop rate, measures how much energy rose
/// (frame-over-frame, restricted to the chosen band) at every frequency bin,
/// and fires an event whenever that "onset strength" spikes well above its
/// own recent rolling average. This is the same general approach real beat
/// trackers (aubio, essentia) use internally — a real per-frequency-bin
/// analysis instead of a handful of overlapping IIR low-pass filters — while
/// staying pure Dart (no native/FFI dependency, so it runs identically on
/// Android, Windows, and any future iOS build).
class BeatDetectorService {
  static const _sampleRate = 44100.0;
  // A size-2048 FFT at 44.1kHz gives ~21.5Hz/bin — enough to separate a kick
  // drum's narrow ~40-150Hz pocket from the wider "bass" band below.
  static const _fftSize = 2048;
  // 512-sample hop (~11.6ms, 75% overlap) — frequent enough for tight onset
  // timing without needing a bigger FFT (which would blur that timing).
  static const _hopSize = 512;
  static const _hopMs = _hopSize / _sampleRate * 1000;

  // Band edges in Hz — same split points the old IIR-filter version used, now
  // applied as precise FFT bin ranges instead of an approximate time-domain
  // filter cascade.
  static const _subBassHz = 20.0; // skip the DC/near-DC bin
  static const _kickLowHz = 40.0;
  static const _kickHighHz = 150.0;
  static const _bassHighHz = 250.0;
  static const _midHighHz = 2000.0;

  // The rolling mean/variance are tracked as an exponential moving average
  // rather than a plain sliding-window average — a window average visibly
  // "jitters" as individual old samples drop out and new ones enter (each
  // one swings the average by its own full weight); an EMA blends every new
  // frame in by a small amount instead, so the displayed sensitivity/
  // threshold reading moves smoothly rather than jumping every ~12ms.
  static const _emaTauMs = 1200.0;
  static const _warmupMs = 600.0;

  static final FFT _fft = FFT(_fftSize);
  static final Float64List _hannWindow = Window.hanning(_fftSize);

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _pcmSub;
  final _beatController = StreamController<DateTime>.broadcast();
  final _meterController = StreamController<BeatMeterSample>.broadcast();
  double? _emaMean;
  double _emaVariance = 0;
  int _frameCount = 0;
  DateTime? _lastBeat;

  Float64List _ring = Float64List(_fftSize);
  int _ringWrite = 0;
  int _samplesBuffered = 0;
  int _samplesSinceFrame = 0;
  Float64List? _prevMagnitude;

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
      _emaMean = null;
      _emaVariance = 0;
      _frameCount = 0;
      _lastBeat = null;
      _ring = Float64List(_fftSize);
      _ringWrite = 0;
      _samplesBuffered = 0;
      _samplesSinceFrame = 0;
      _prevMagnitude = null;
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
    final byteData = ByteData.sublistView(chunk);
    for (var i = 0; i + 1 < chunk.length; i += 2) {
      final sample = byteData.getInt16(i, Endian.little) / 32768.0;
      _ring[_ringWrite] = sample;
      _ringWrite = (_ringWrite + 1) % _fftSize;
      if (_samplesBuffered < _fftSize) _samplesBuffered++;
      _samplesSinceFrame++;
      if (_samplesBuffered == _fftSize && _samplesSinceFrame >= _hopSize) {
        _samplesSinceFrame = 0;
        _processFrame();
      }
    }
  }

  /// Cached because the ranges are fixed and the meter now asks for all of
  /// them on every one of the ~86 frames a second.
  static final Map<BeatFrequencyBand, (int, int)> _binRangeCache = {};

  (int, int) _binRangeFor(BeatFrequencyBand band) {
    return _binRangeCache.putIfAbsent(band, () => _computeBinRange(band));
  }

  (int, int) _computeBinRange(BeatFrequencyBand frequencyBand) {
    final nyquistBin = _fftSize ~/ 2;
    double loHz;
    double hiHz;
    switch (frequencyBand) {
      case BeatFrequencyBand.kick:
        loHz = _kickLowHz;
        hiHz = _kickHighHz;
        break;
      case BeatFrequencyBand.bass:
        loHz = _subBassHz;
        hiHz = _bassHighHz;
        break;
      case BeatFrequencyBand.mid:
        loHz = _bassHighHz;
        hiHz = _midHighHz;
        break;
      case BeatFrequencyBand.high:
        loHz = _midHighHz;
        hiHz = _sampleRate / 2;
        break;
      case BeatFrequencyBand.overall:
        loHz = _subBassHz;
        hiHz = _sampleRate / 2;
        break;
    }
    final loBin = _fft.indexOfFrequency(loHz, _sampleRate).floor().clamp(1, nyquistBin);
    final hiBin = _fft.indexOfFrequency(hiHz, _sampleRate).ceil().clamp(loBin, nyquistBin);
    return (loBin, hiBin);
  }

  void _processFrame() {
    final windowed = Float64List(_fftSize);
    for (var i = 0; i < _fftSize; i++) {
      windowed[i] = _ring[(_ringWrite + i) % _fftSize] * _hannWindow[i];
    }
    final magnitude = _fft.realFft(windowed).magnitudes();

    final prev = _prevMagnitude;
    // Every band, not just the selected one: the meter draws them all so
    // you can see where the beat actually is before choosing which to
    // follow. The extra work is a second sweep of the spectrum per frame,
    // which is nothing next to the FFT itself.
    final fluxes = <BeatFrequencyBand, double>{};
    for (final band in BeatFrequencyBand.values) {
      var sum = 0.0;
      if (prev != null) {
        final (loBin, hiBin) = _binRangeFor(band);
        for (var k = loBin; k <= hiBin; k++) {
          // Spectral flux: only positive (energy-rising) changes count as
          // onset evidence — a bin fading out shouldn't cancel one growing.
          final diff = magnitude[k] - prev[k];
          if (diff > 0) sum += diff;
        }
      }
      fluxes[band] = sum;
    }
    _prevMagnitude = magnitude;
    _handleFluxSample(fluxes);
  }

  /// Per-band rolling averages, so each bar is drawn against its own norm
  /// rather than against whatever the loudest band happens to be doing.
  final Map<BeatFrequencyBand, double> _bandEma = {};

  Map<BeatFrequencyBand, BandLevel> _bandLevels(Map<BeatFrequencyBand, double> fluxes, double alpha) {
    final levels = <BeatFrequencyBand, BandLevel>{};
    for (final entry in fluxes.entries) {
      final previous = _bandEma[entry.key];
      final mean = previous == null ? entry.value : previous + alpha * (entry.value - previous);
      _bandEma[entry.key] = mean;
      levels[entry.key] = BandLevel(db: _toDb(entry.value), avg: _toDb(mean));
    }
    return levels;
  }

  static double _toDb(double linear) => linear > 1e-9 ? 20 * math.log(linear) / math.ln10 : -200.0;

  void _handleFluxSample(Map<BeatFrequencyBand, double> fluxes) {
    _frameCount++;
    // Detection follows the selected band; the rest are carried along
    // purely so the meter can draw them.
    final flux = fluxes[frequencyBand] ?? 0;
    final alpha = 1 - math.exp(-_hopMs / _emaTauMs);
    final bands = _bandLevels(fluxes, alpha);

    final mean = _emaMean;
    if (mean == null) {
      _emaMean = flux;
      _emaVariance = 0;
    } else {
      // Exponential moving average/variance: each new frame nudges the
      // running mean by `alpha`, rather than a sample dropping out of a
      // window and yanking the average by its own full weight — this is
      // what keeps the meter's avg/threshold display smooth instead of
      // visibly stepping every ~12ms.
      final delta = flux - mean;
      final newMean = mean + alpha * delta;
      _emaMean = newMean;
      final delta2 = flux - newMean;
      _emaVariance = (1 - alpha) * (_emaVariance + alpha * delta * delta2);
    }

    final warmupFrames = (_warmupMs / _hopMs).round();
    if (_frameCount < warmupFrames) {
      // Rolling stats still warming up — show the raw level, no beats yet.
      final db = _toDb(flux);
      _meterController.add(BeatMeterSample(
        db: db,
        avg: db,
        threshold: db,
        requiredRise: 0,
        isBeat: false,
        band: frequencyBand,
        bands: bands,
      ));
      return;
    }

    // Spectral flux is near-zero on most frames (silence, or audio whose
    // spectrum simply isn't changing) and spikes hard on genuine onsets —
    // unlike a raw loudness reading, a fixed "rise in dB above the mean"
    // doesn't work here, since the mean itself sits so close to zero that
    // almost any residual noise would count as a huge relative rise. A
    // statistical outlier test (mean + k·standard deviation) stays correctly
    // calibrated to how noisy/eventful the recent audio has actually been.
    final stddev = math.sqrt(_emaVariance);

    // Higher sensitivity -> fewer standard deviations above the mean are
    // enough to count as a beat. The top of the range (2.5) is calibrated
    // against synthetic click tracks: it still reliably catches real
    // onsets. The bottom was 6.0 and turned out not to be strict enough in
    // a loud room, where a busy mix crosses it constantly — 9.0 leaves
    // room to wind it right down to "only the hardest hits".
    final k = 9.0 - sensitivity * 6.5;
    final thresholdFlux = _emaMean! + k * stddev;

    final now = DateTime.now();
    final pastRefractoryPeriod =
        _lastBeat == null || now.difference(_lastBeat!) > const Duration(milliseconds: 250);
    final isBeat = flux > thresholdFlux && pastRefractoryPeriod;
    if (isBeat) {
      _lastBeat = now;
      _beatController.add(now);
    }

    final avgDb = _toDb(_emaMean!);
    final thresholdDb = _toDb(thresholdFlux);
    _meterController.add(
      BeatMeterSample(
        db: _toDb(flux),
        avg: avgDb,
        threshold: thresholdDb,
        requiredRise: thresholdDb - avgDb,
        isBeat: isBeat,
        band: frequencyBand,
        bands: bands,
      ),
    );
  }

  void dispose() {
    _pcmSub?.cancel();
    _recorder.dispose();
    _beatController.close();
    _meterController.close();
  }
}
