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

  /// Each zone plays either a saved chase *or* a whole bank. Both are kept
  /// as separate fields rather than one tagged id so projects saved before
  /// banks were allowed keep loading unchanged; the editor only ever sets
  /// one of the pair, and the chase wins if somehow both are set.
  final String? baseChaseId;
  final String? baseBankId;
  final double baseBpm;
  final ThresholdMode thresholdMode;

  /// Fade time for the base chase — overrides its own/its bank's per-step
  /// fade while this program is running.
  final Duration baseFade;

  final String? fasterChaseId;
  final String? fasterBankId;
  final double fasterThreshold; // % or BPM above baseBpm, per thresholdMode
  final Duration fasterHold;
  final Duration fasterFade;

  final String? slowerChaseId;
  final String? slowerBankId;
  final double slowerThreshold; // % or BPM below baseBpm, per thresholdMode
  final Duration slowerHold;
  final Duration slowerFade;

  /// How long the rig takes to fade out when the music stops. Deliberately
  /// its own (longer) setting rather than reusing a zone's fade — a show
  /// dying out should look like a sunset, not a step.
  final Duration blackoutFade;

  const SmartProgram({
    required this.id,
    required this.name,
    this.baseChaseId,
    this.baseBankId,
    this.baseBpm = 120,
    this.thresholdMode = ThresholdMode.percent,
    this.baseFade = const Duration(milliseconds: 300),
    this.fasterChaseId,
    this.fasterBankId,
    this.fasterThreshold = 10,
    this.fasterHold = const Duration(seconds: 3),
    this.fasterFade = const Duration(milliseconds: 300),
    this.slowerChaseId,
    this.slowerBankId,
    this.slowerThreshold = 10,
    this.slowerHold = const Duration(seconds: 3),
    this.slowerFade = const Duration(milliseconds: 300),
    this.blackoutFade = const Duration(seconds: 3),
  });

  bool get hasBaseTarget => baseChaseId != null || baseBankId != null;

  /// The BPM at/above which the "faster" chase should take over.
  double get fasterTriggerBpm =>
      thresholdMode == ThresholdMode.percent ? baseBpm * (1 + fasterThreshold / 100) : baseBpm + fasterThreshold;

  /// The BPM at/below which the "slower" chase should take over.
  double get slowerTriggerBpm =>
      thresholdMode == ThresholdMode.percent ? baseBpm * (1 - slowerThreshold / 100) : baseBpm - slowerThreshold;

  ProgramTarget? get baseTarget => ProgramTarget.from(chaseId: baseChaseId, bankId: baseBankId);
  ProgramTarget? get fasterTarget => ProgramTarget.from(chaseId: fasterChaseId, bankId: fasterBankId);
  ProgramTarget? get slowerTarget => ProgramTarget.from(chaseId: slowerChaseId, bankId: slowerBankId);

  /// [clearBase]/[clearFaster]/[clearSlower] null out *both* ids of that
  /// zone — a zone plays one thing, so setting a bank has to drop the chase
  /// and vice versa.
  SmartProgram copyWith({
    String? name,
    String? baseChaseId,
    String? baseBankId,
    double? baseBpm,
    ThresholdMode? thresholdMode,
    Duration? baseFade,
    String? fasterChaseId,
    String? fasterBankId,
    double? fasterThreshold,
    Duration? fasterHold,
    Duration? fasterFade,
    String? slowerChaseId,
    String? slowerBankId,
    double? slowerThreshold,
    Duration? slowerHold,
    Duration? slowerFade,
    Duration? blackoutFade,
    bool clearBase = false,
    bool clearFaster = false,
    bool clearSlower = false,
  }) {
    return SmartProgram(
      id: id,
      name: name ?? this.name,
      baseChaseId: clearBase ? baseChaseId : (baseChaseId ?? this.baseChaseId),
      baseBankId: clearBase ? baseBankId : (baseBankId ?? this.baseBankId),
      baseBpm: baseBpm ?? this.baseBpm,
      thresholdMode: thresholdMode ?? this.thresholdMode,
      baseFade: baseFade ?? this.baseFade,
      fasterChaseId: clearFaster ? fasterChaseId : (fasterChaseId ?? this.fasterChaseId),
      fasterBankId: clearFaster ? fasterBankId : (fasterBankId ?? this.fasterBankId),
      fasterThreshold: fasterThreshold ?? this.fasterThreshold,
      fasterHold: fasterHold ?? this.fasterHold,
      fasterFade: fasterFade ?? this.fasterFade,
      slowerChaseId: clearSlower ? slowerChaseId : (slowerChaseId ?? this.slowerChaseId),
      slowerBankId: clearSlower ? slowerBankId : (slowerBankId ?? this.slowerBankId),
      slowerThreshold: slowerThreshold ?? this.slowerThreshold,
      slowerHold: slowerHold ?? this.slowerHold,
      slowerFade: slowerFade ?? this.slowerFade,
      blackoutFade: blackoutFade ?? this.blackoutFade,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseChaseId': baseChaseId,
    'baseBankId': baseBankId,
    'baseBpm': baseBpm,
    'thresholdMode': thresholdMode.name,
    'baseFadeMs': baseFade.inMilliseconds,
    'fasterChaseId': fasterChaseId,
    'fasterBankId': fasterBankId,
    'fasterThreshold': fasterThreshold,
    'fasterHoldMs': fasterHold.inMilliseconds,
    'fasterFadeMs': fasterFade.inMilliseconds,
    'slowerChaseId': slowerChaseId,
    'slowerBankId': slowerBankId,
    'slowerThreshold': slowerThreshold,
    'slowerHoldMs': slowerHold.inMilliseconds,
    'slowerFadeMs': slowerFade.inMilliseconds,
    'blackoutFadeMs': blackoutFade.inMilliseconds,
  };

  factory SmartProgram.fromJson(Map<String, dynamic> json) {
    // Older saves had one shared "fadeMs" for all three zones — fall back to
    // that if a zone-specific fade isn't present yet.
    final legacyFadeMs = json['fadeMs'] as int? ?? 300;
    return SmartProgram(
      id: json['id'] as String,
      name: json['name'] as String,
      baseChaseId: json['baseChaseId'] as String?,
      baseBankId: json['baseBankId'] as String?,
      baseBpm: (json['baseBpm'] as num?)?.toDouble() ?? 120,
      thresholdMode: ThresholdMode.values.firstWhere(
        (m) => m.name == json['thresholdMode'],
        orElse: () => ThresholdMode.percent,
      ),
      baseFade: Duration(milliseconds: json['baseFadeMs'] as int? ?? legacyFadeMs),
      fasterChaseId: json['fasterChaseId'] as String?,
      fasterBankId: json['fasterBankId'] as String?,
      fasterThreshold: (json['fasterThreshold'] as num?)?.toDouble() ?? 10,
      fasterHold: Duration(milliseconds: json['fasterHoldMs'] as int? ?? 3000),
      fasterFade: Duration(milliseconds: json['fasterFadeMs'] as int? ?? legacyFadeMs),
      slowerChaseId: json['slowerChaseId'] as String?,
      slowerBankId: json['slowerBankId'] as String?,
      slowerThreshold: (json['slowerThreshold'] as num?)?.toDouble() ?? 10,
      slowerHold: Duration(milliseconds: json['slowerHoldMs'] as int? ?? 3000),
      slowerFade: Duration(milliseconds: json['slowerFadeMs'] as int? ?? legacyFadeMs),
      blackoutFade: Duration(milliseconds: json['blackoutFadeMs'] as int? ?? 3000),
    );
  }
}

/// What one Smart Program zone plays: a saved chase, or a whole bank.
class ProgramTarget {
  final String id;
  final bool isBank;

  const ProgramTarget({required this.id, required this.isBank});

  static ProgramTarget? from({String? chaseId, String? bankId}) {
    if (chaseId != null) return ProgramTarget(id: chaseId, isBank: false);
    if (bankId != null) return ProgramTarget(id: bankId, isBank: true);
    return null;
  }
}
