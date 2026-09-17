import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';
import 'package:record/record.dart';

import 'onset_baseline.dart';

/// How fast the detector's rolling baseline chases the music.
///
/// The threshold is "mean + k·stddev" of recent onset strength, and this is
/// how recent "recent" means. It's exposed because there is no single right
/// answer: a short memory keeps the bar low between beats and catches a
/// dense mix that a long one averages into a plateau, while a long memory
/// is steadier and less likely to latch onto a noisy room.
enum BeatAdaptSpeed {
  /// ~0.3s. Reacts within a bar — the one to try when beats are being lost
  /// in loud, busy music.
  fast,

  /// ~1.2s. The original behaviour.
  normal,

  /// ~3s. Rides over a passage that changes texture a lot.
  slow,

  /// Effectively no moving average: a 30-second memory, so the baseline is
  /// the whole song rather than the last few bars. Steadiest, but it can't
  /// follow a set that changes volume.
  off;

  double get tauMs => switch (this) {
    BeatAdaptSpeed.fast => 300,
    BeatAdaptSpeed.normal => 1200,
    BeatAdaptSpeed.slow => 3000,
    BeatAdaptSpeed.off => 30000,
  };

  String get label => switch (this) {
    BeatAdaptSpeed.fast => 'Fast',
    BeatAdaptSpeed.normal => 'Normal',
    BeatAdaptSpeed.slow => 'Slow',
    BeatAdaptSpeed.off => 'Off',
  };
}

/// Which part of the audio spectrum the detector reacts to — lets a kick
/// drum (bass), snare/vocals (mid), or hi-hats/cymbals (high) drive the
/// sync instead of only overall loudness.
enum BeatFrequencyBand {
  overall,
  kick,

  /// A narrow 60-120Hz window around where a kick drum's fundamental
  /// actually sits. [kick] is 40-150Hz, wide enough to also take in a bass
  /// guitar's low notes and a floor tom — fine in most rooms, but on a
  /// dense mix those keep the baseline up between kicks and the detector
  /// starts losing them. This band trades that tolerance for a signal that
  /// is very nearly only the kick.
  kickTight,
  bass,
  mid,
  high;

  String get label => switch (this) {
    BeatFrequencyBand.overall => 'Volume',
    BeatFrequencyBand.kick => 'Kick/Drum',
    BeatFrequencyBand.kickTight => 'Kick Tight',
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
  // The tight kick window: above the sub-bass rumble a PA puts out more or
  // less continuously, below the low mids where a bass guitar's body and a
  // snare's weight start.
  static const _kickTightLowHz = 60.0;
  static const _kickTightHighHz = 120.0;
  static const _bassHighHz = 250.0;
  static const _midHighHz = 2000.0;

  static const _warmupMs = 600.0;

  static final FFT _fft = FFT(_fftSize);
  static final Float64List _hannWindow = Window.hanning(_fftSize);

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _pcmSub;
  final _beatController = StreamController<DateTime>.broadcast();
  final _meterController = StreamController<BeatMeterSample>.broadcast();
  final OnsetBaseline _baseline = OnsetBaseline();

  /// A ~300ms level of the selected band, the "is anything happening in
  /// here" reading the escape hatch needs.
  static const _fastLevelMs = 300.0;
  double _fastLevel = 0;
  DateTime? _listeningSince;
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

  /// How quickly the rolling baseline follows the music.
  BeatAdaptSpeed adaptSpeed = BeatAdaptSpeed.normal;

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

      final stream = await _openStream();
      _baseline.reset();
      _frameCount = 0;
      _lastBeat = null;
      _fastLevel = 0;
      _listeningSince = DateTime.now();
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

  /// Android input sources, best first.
  ///
  /// [AndroidAudioSource.unprocessed] is the one we actually want: it's the
  /// source Android defines as raw — no automatic gain control, no noise
  /// suppression, no echo canceller. All of that processing exists to
  /// flatter a voice, and all of it works against onset detection: AGC
  /// pumps the level back up between beats so the kick stops standing out
  /// from its own baseline, and noise suppression treats a steady loud room
  /// as the thing to remove. It's optional, though — a device only honours
  /// it if it reports PROPERTY_SUPPORT_AUDIO_SOURCE_UNPROCESSED, and plenty
  /// of phones (the P20 Pro among them) don't.
  ///
  /// [AndroidAudioSource.camcorder] is the fallback because it's the other
  /// source meant for recording the room rather than the user — it points
  /// at the mic that faces away from the face and skips voice processing —
  /// and it's far more widely implemented, though a device without a camera
  /// mic can still refuse it.
  ///
  /// [AndroidAudioSource.mic] is last because it always exists. It's the
  /// old behaviour, processing and all.
  static const _androidSources = [
    AndroidAudioSource.unprocessed,
    AndroidAudioSource.camcorder,
    AndroidAudioSource.mic,
  ];

  static RecordConfig _configFor(AndroidAudioSource source) => RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    numChannels: 1,
    sampleRate: 44100,
    androidConfig: AndroidRecordConfig(
      audioSource: source,
      // Don't let the recorder open a Bluetooth SCO link. It would move
      // capture to whatever headset is paired and drop the whole stream to
      // narrowband — 8 or 16kHz, which throws away the spectrum the mid and
      // high bands live in — and on the way it mutes the A2DP audio the
      // music is playing over. We want the device's own mic, in the room.
      manageBluetooth: false,
    ),
  );

  /// Opens the capture stream, walking [_androidSources] until one opens.
  ///
  /// A source the device won't give us throws out of `startStream`, and the
  /// next one gets its turn. The chain ends at plain `mic`, so this only
  /// throws if capture is impossible at all — and the error that surfaces
  /// is `mic`'s, which is the one worth showing. On every other platform
  /// the Android block is ignored and the first attempt is the only one.
  Future<Stream<Uint8List>> _openStream() async {
    for (var i = 0; i < _androidSources.length; i++) {
      try {
        return await _recorder.startStream(_configFor(_androidSources[i]));
      } catch (_) {
        if (i == _androidSources.length - 1) rethrow;
        // Leave nothing half-open behind before asking for the next source.
        try {
          await _recorder.stop();
        } catch (_) {
          // Never got far enough to need stopping.
        }
      }
    }
    // Unreachable: the loop either returns or rethrows on its last pass.
    throw StateError('No audio source to try');
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
      case BeatFrequencyBand.kickTight:
        loHz = _kickTightLowHz;
        hiHz = _kickTightHighHz;
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

  static double _square(double value) => value * value;

  static double _toDb(double linear) => linear > 1e-9 ? 20 * math.log(linear) / math.ln10 : -200.0;

  void _handleFluxSample(Map<BeatFrequencyBand, double> fluxes) {
    _frameCount++;
    // Detection follows the selected band; the rest are carried along
    // purely so the meter can draw them.
    final flux = fluxes[frequencyBand] ?? 0;
    // The rolling mean/variance are an exponential moving average rather
    // than a sliding window: a window average visibly jitters as old
    // samples drop out (each swings it by its own full weight), while an
    // EMA blends each new frame in by `alpha`, so the threshold reading
    // moves smoothly rather than stepping every ~12ms. How much memory it
    // has is [adaptSpeed] — see there for why that's a setting.
    final alpha = 1 - math.exp(-_hopMs / adaptSpeed.tauMs);
    final bands = _bandLevels(fluxes, alpha);

    // A short level, purely to answer "is this room still making noise" for
    // the escape hatch below.
    _fastLevel += (1 - math.exp(-_hopMs / _fastLevelMs)) * (flux - _fastLevel);

    final now = DateTime.now();
    // The bar can be left somewhere nothing musical will ever reach — see
    // [shouldForgetBaseline]. Forgetting re-runs the warmup, so no beats go
    // out while the statistics re-form.
    final since = now.difference(_lastBeat ?? _listeningSince ?? now);
    if (shouldForgetBaseline(
      memoryMs: adaptSpeed.tauMs,
      secondsSinceBeat: since.inMilliseconds / 1000,
      fastLevel: _fastLevel,
      mean: _baseline.mean,
    )) {
      _baseline.reset();
      _frameCount = 1;
      _lastBeat = now;
    }

    // Exponential moving average/variance rather than a sliding window:
    // each new frame nudges the running mean by `alpha` instead of a sample
    // dropping out and yanking the average by its own full weight, so the
    // meter's avg/threshold move smoothly rather than stepping every ~12ms.
    _baseline.learn(flux, alpha);

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
    //
    // Higher sensitivity -> fewer standard deviations above the mean are
    // enough to count as a beat.
    //
    // The curve is quadratic rather than straight, and that matters. It was
    // `6.0 - s*3.5`; widening the quiet end to 9.0 by straightening it to
    // `9.0 - s*6.5` also dragged the *middle* up — the default 0.6 went
    // from 3.9 to 5.1 standard deviations, which is why the first live gig
    // kept losing beats the meter could plainly see. Squaring the distance
    // from full sensitivity keeps the working range where it was (0.6 now
    // gives 3.5) while still reaching 9.0 at the very bottom for a room
    // loud enough to need it.
    final k = 2.5 + 6.5 * _square(1 - sensitivity.clamp(0.0, 1.0));
    final thresholdFlux = _baseline.thresholdAt(k);

    final pastRefractoryPeriod =
        _lastBeat == null || now.difference(_lastBeat!) > const Duration(milliseconds: 250);
    final isBeat = flux > thresholdFlux && pastRefractoryPeriod;
    if (isBeat) {
      _lastBeat = now;
      _beatController.add(now);
    }

    final avgDb = _toDb(_baseline.mean ?? 0);
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
