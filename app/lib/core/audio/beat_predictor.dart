import 'dart:async';

import 'beat_detector.dart';
import 'tempo_estimator.dart';

/// Fills in the beats the detector never heard.
///
/// [BeatDetectorService] only reports a beat once its onset actually crosses
/// the threshold — a quiet passage, a bass note buried under the mix, or
/// just an unlucky microphone position can drop one, and every consumer
/// downstream (a beat-synced chase waiting for the next event) simply stalls
/// until the next real onset arrives. That stall is audible: the rig holds
/// a look a beat and a half too long, then double-steps to catch up.
///
/// This sits between the detector and its consumers. It relays every real
/// beat straight through, and — once a handful of them agree on a tempo —
/// also locks onto that tempo's period and keeps emitting synthetic beats on
/// schedule for as long as real ones stop arriving. A real beat, whenever it
/// does show up, immediately re-phases the lock to it rather than averaging
/// it in, so a genuine tempo change is followed on the very next beat rather
/// than fought for several bars.
///
/// [enabled] gates prediction only — real beats always pass through, so
/// leaving it off (the default) is exactly today's passthrough behaviour.
class BeatPredictor {
  /// How many beats in a row this will predict with no real beat to confirm
  /// them. Bounded so a song that has actually stopped doesn't get an
  /// indefinitely running metronome invented for it — four is the same
  /// ceiling [estimateTempo] uses for folding a missed beat back in.
  static const _maxConsecutivePredictions = 4;

  /// A gap this large between real beats means a new song (or silence)
  /// rather than a slow tempo — matches [BeatTempoTracker]'s own cutoff, so
  /// the two never disagree about when the old tempo stopped applying.
  static const _staleAfter = Duration(seconds: 2);

  final List<DateTime> _recentBeats = [];
  final _controller = StreamController<DateTime>.broadcast();
  StreamSubscription<DateTime>? _sub;
  Timer? _predictionTimer;
  Duration? _lockedPeriod;
  int _consecutivePredictions = 0;
  bool _enabled = false;

  BeatPredictor(BeatDetectorService service) {
    _sub = service.beatEvents.listen(_onRealBeat);
  }

  /// Real beats, plus — while [enabled] and locked onto a tempo — the
  /// predicted ones filling the gaps. One broadcast stream so every
  /// consumer (a beat-synced chase, a preview) sees the same timeline.
  Stream<DateTime> get events => _controller.stream;

  bool get enabled => _enabled;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) _cancelPrediction();
  }

  void _onRealBeat(DateTime at) {
    _controller.add(at);
    _consecutivePredictions = 0;
    _cancelPrediction();

    if (_recentBeats.isNotEmpty && at.difference(_recentBeats.last) > _staleAfter) {
      _recentBeats.clear();
    }
    _recentBeats.add(at);
    if (_recentBeats.length > 12) _recentBeats.removeAt(0);

    if (!_enabled) return;
    final estimate = estimateTempo(_recentBeats);
    if (estimate == null || !estimate.isConfident) {
      _lockedPeriod = null;
      return;
    }
    _lockedPeriod = Duration(microseconds: (60000000 / estimate.bpm).round());
    _scheduleNextPrediction(from: at);
  }

  /// Arms a one-shot timer for the next predicted beat, [_lockedPeriod]
  /// after [from]. Re-armed from inside its own callback rather than a
  /// `Timer.periodic`, so a real beat landing in between can always cancel
  /// and restart the chain cleanly instead of two timers racing.
  void _scheduleNextPrediction({required DateTime from}) {
    final period = _lockedPeriod;
    if (period == null || _consecutivePredictions >= _maxConsecutivePredictions) return;
    final due = from.add(period);
    final delay = due.difference(DateTime.now());
    _predictionTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _consecutivePredictions++;
      _controller.add(due);
      _scheduleNextPrediction(from: due);
    });
  }

  void _cancelPrediction() {
    _predictionTimer?.cancel();
    _predictionTimer = null;
  }

  void dispose() {
    _cancelPrediction();
    _sub?.cancel();
    _controller.close();
  }
}
