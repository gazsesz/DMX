import 'beat_detector.dart';

/// How the microphone beat detector listens: how eagerly it fires, which
/// part of the spectrum it reacts to, and how long its baseline remembers.
///
/// Kept twice (Gabor's choice, v1.56.0): the tablet remembers the last one
/// (it belongs to the mic and the room), and the project saves it too, so a
/// show tuned for a venue brings its tuning back — on load the project's
/// wins. The silence floor is not part of it; that stays device-only.
class BeatTuning {
  final double sensitivity;
  final BeatFrequencyBand band;
  final BeatAdaptSpeed adaptSpeed;

  const BeatTuning({
    this.sensitivity = 0.6,
    this.band = BeatFrequencyBand.overall,
    this.adaptSpeed = BeatAdaptSpeed.normal,
  });

  BeatTuning copyWith({double? sensitivity, BeatFrequencyBand? band, BeatAdaptSpeed? adaptSpeed}) => BeatTuning(
    sensitivity: sensitivity ?? this.sensitivity,
    band: band ?? this.band,
    adaptSpeed: adaptSpeed ?? this.adaptSpeed,
  );

  void applyTo(BeatDetectorService detector) {
    detector.sensitivity = sensitivity;
    detector.frequencyBand = band;
    detector.adaptSpeed = adaptSpeed;
  }

  Map<String, dynamic> toJson() => {'sensitivity': sensitivity, 'band': band.name, 'adaptSpeed': adaptSpeed.name};

  /// Tolerant: anything missing or unknown falls back to the default.
  factory BeatTuning.fromJson(Map<String, dynamic> json) {
    const base = BeatTuning();
    return BeatTuning(
      sensitivity: ((json['sensitivity'] as num?)?.toDouble() ?? base.sensitivity).clamp(0.0, 1.0),
      band: BeatFrequencyBand.values.asNameMap()[json['band']] ?? base.band,
      adaptSpeed: BeatAdaptSpeed.values.asNameMap()[json['adaptSpeed']] ?? base.adaptSpeed,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BeatTuning && other.sensitivity == sensitivity && other.band == band && other.adaptSpeed == adaptSpeed;

  @override
  int get hashCode => Object.hash(sensitivity, band, adaptSpeed);
}
