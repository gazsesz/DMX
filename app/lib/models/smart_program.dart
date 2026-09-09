/// Whether a Smart Program's tempo thresholds are expressed as a percentage
/// change from the base BPM, or as a flat BPM difference.
enum ThresholdMode { percent, bpm }

/// A tempo-aware program: a base chase plays at the song's normal speed,
/// then hands off to a faster/slower chase when the live beat tempo drifts
/// away from [baseBpm] by more than the configured threshold and *stays*
/// there for that direction's hold duration — so a brief fluctuation doesn't
/// cause flicker between chases.
class SmartProgram {
  final String id;
  final String name;
  final String? baseChaseId;
  final double baseBpm;
  final ThresholdMode thresholdMode;

  /// Fade time for the base chase — overrides its own/its bank's per-step
  /// fade while this program is running.
  final Duration baseFade;

  final String? fasterChaseId;
  final double fasterThreshold; // % or BPM above baseBpm, per thresholdMode
  final Duration fasterHold;
  final Duration fasterFade;

  final String? slowerChaseId;
  final double slowerThreshold; // % or BPM below baseBpm, per thresholdMode
  final Duration slowerHold;
  final Duration slowerFade;

  const SmartProgram({
    required this.id,
    required this.name,
    this.baseChaseId,
    this.baseBpm = 120,
    this.thresholdMode = ThresholdMode.percent,
    this.baseFade = const Duration(milliseconds: 300),
    this.fasterChaseId,
    this.fasterThreshold = 10,
    this.fasterHold = const Duration(seconds: 3),
    this.fasterFade = const Duration(milliseconds: 300),
    this.slowerChaseId,
    this.slowerThreshold = 10,
    this.slowerHold = const Duration(seconds: 3),
    this.slowerFade = const Duration(milliseconds: 300),
  });

  /// The BPM at/above which the "faster" chase should take over.
  double get fasterTriggerBpm =>
      thresholdMode == ThresholdMode.percent ? baseBpm * (1 + fasterThreshold / 100) : baseBpm + fasterThreshold;

  /// The BPM at/below which the "slower" chase should take over.
  double get slowerTriggerBpm =>
      thresholdMode == ThresholdMode.percent ? baseBpm * (1 - slowerThreshold / 100) : baseBpm - slowerThreshold;

  SmartProgram copyWith({
    String? name,
    String? baseChaseId,
    double? baseBpm,
    ThresholdMode? thresholdMode,
    Duration? baseFade,
    String? fasterChaseId,
    double? fasterThreshold,
    Duration? fasterHold,
    Duration? fasterFade,
    String? slowerChaseId,
    double? slowerThreshold,
    Duration? slowerHold,
    Duration? slowerFade,
    bool clearFasterChase = false,
    bool clearSlowerChase = false,
  }) {
    return SmartProgram(
      id: id,
      name: name ?? this.name,
      baseChaseId: baseChaseId ?? this.baseChaseId,
      baseBpm: baseBpm ?? this.baseBpm,
      thresholdMode: thresholdMode ?? this.thresholdMode,
      baseFade: baseFade ?? this.baseFade,
      fasterChaseId: clearFasterChase ? null : (fasterChaseId ?? this.fasterChaseId),
      fasterThreshold: fasterThreshold ?? this.fasterThreshold,
      fasterHold: fasterHold ?? this.fasterHold,
      fasterFade: fasterFade ?? this.fasterFade,
      slowerChaseId: clearSlowerChase ? null : (slowerChaseId ?? this.slowerChaseId),
      slowerThreshold: slowerThreshold ?? this.slowerThreshold,
      slowerHold: slowerHold ?? this.slowerHold,
      slowerFade: slowerFade ?? this.slowerFade,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseChaseId': baseChaseId,
    'baseBpm': baseBpm,
    'thresholdMode': thresholdMode.name,
    'baseFadeMs': baseFade.inMilliseconds,
    'fasterChaseId': fasterChaseId,
    'fasterThreshold': fasterThreshold,
    'fasterHoldMs': fasterHold.inMilliseconds,
    'fasterFadeMs': fasterFade.inMilliseconds,
    'slowerChaseId': slowerChaseId,
    'slowerThreshold': slowerThreshold,
    'slowerHoldMs': slowerHold.inMilliseconds,
    'slowerFadeMs': slowerFade.inMilliseconds,
  };

  factory SmartProgram.fromJson(Map<String, dynamic> json) {
    // Older saves had one shared "fadeMs" for all three zones — fall back to
    // that if a zone-specific fade isn't present yet.
    final legacyFadeMs = json['fadeMs'] as int? ?? 300;
    return SmartProgram(
      id: json['id'] as String,
      name: json['name'] as String,
      baseChaseId: json['baseChaseId'] as String?,
      baseBpm: (json['baseBpm'] as num?)?.toDouble() ?? 120,
      thresholdMode: ThresholdMode.values.firstWhere(
        (m) => m.name == json['thresholdMode'],
        orElse: () => ThresholdMode.percent,
      ),
      baseFade: Duration(milliseconds: json['baseFadeMs'] as int? ?? legacyFadeMs),
      fasterChaseId: json['fasterChaseId'] as String?,
      fasterThreshold: (json['fasterThreshold'] as num?)?.toDouble() ?? 10,
      fasterHold: Duration(milliseconds: json['fasterHoldMs'] as int? ?? 3000),
      fasterFade: Duration(milliseconds: json['fasterFadeMs'] as int? ?? legacyFadeMs),
      slowerChaseId: json['slowerChaseId'] as String?,
      slowerThreshold: (json['slowerThreshold'] as num?)?.toDouble() ?? 10,
      slowerHold: Duration(milliseconds: json['slowerHoldMs'] as int? ?? 3000),
      slowerFade: Duration(milliseconds: json['slowerFadeMs'] as int? ?? legacyFadeMs),
    );
  }
}
