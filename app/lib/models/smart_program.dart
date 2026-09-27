import 'layer.dart';

/// Whether a Smart Program's tempo thresholds are expressed as a percentage
/// change from the base BPM, or as a flat BPM difference.
enum ThresholdMode { percent, bpm }

enum SmartProgramZone { base, faster, slower }

/// What one layer plays in each of a Smart Program's three zones. A zone
/// left empty on a layer means that layer keeps its Base through it; a
/// layer with no Base either sits idle whenever its own zone isn't the one
/// playing — e.g. robots that only join in when the song speeds up.
class LayerZoneTargets {
  final String layerId;
  final ProgramTarget? base;
  final ProgramTarget? faster;
  final ProgramTarget? slower;

  const LayerZoneTargets({required this.layerId, this.base, this.faster, this.slower});

  bool get isEmpty => base == null && faster == null && slower == null;

  ProgramTarget? explicit(SmartProgramZone zone) => switch (zone) {
    SmartProgramZone.base => base,
    SmartProgramZone.faster => faster,
    SmartProgramZone.slower => slower,
  };

  /// What this layer actually plays in [zone] — its own target for it, or
  /// its Base when it has none.
  ProgramTarget? effective(SmartProgramZone zone) => explicit(zone) ?? base;

  /// Whether [effective] for [zone] is the Base standing in for a missing
  /// zone target — worth saying so on screen.
  bool fallsBackToBase(SmartProgramZone zone) =>
      zone != SmartProgramZone.base && explicit(zone) == null && base != null;

  LayerZoneTargets withZone(SmartProgramZone zone, ProgramTarget? target) => LayerZoneTargets(
    layerId: layerId,
    base: zone == SmartProgramZone.base ? target : base,
    faster: zone == SmartProgramZone.faster ? target : faster,
    slower: zone == SmartProgramZone.slower ? target : slower,
  );

  Map<String, dynamic> toJson() => {
    'layerId': layerId,
    'baseChaseId': base?.chaseId,
    'baseBankId': base?.bankId,
    if (base?.chaseLane != null) 'baseChaseLane': base!.chaseLane,
    'fasterChaseId': faster?.chaseId,
    'fasterBankId': faster?.bankId,
    if (faster?.chaseLane != null) 'fasterChaseLane': faster!.chaseLane,
    'slowerChaseId': slower?.chaseId,
    'slowerBankId': slower?.bankId,
    if (slower?.chaseLane != null) 'slowerChaseLane': slower!.chaseLane,
  };

  factory LayerZoneTargets.fromJson(Map<String, dynamic> json) => LayerZoneTargets(
    layerId: json['layerId'] as String,
    base: _targetFromJson(json, 'base'),
    faster: _targetFromJson(json, 'faster'),
    slower: _targetFromJson(json, 'slower'),
  );
}

ProgramTarget? _targetFromJson(Map<String, dynamic> json, String zone) => ProgramTarget.from(
  chaseId: json['${zone}ChaseId'] as String?,
  bankId: json['${zone}BankId'] as String?,
  chaseLane: json['${zone}ChaseLane'] as String?,
);

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
  final String? baseChaseLane;
  final double baseBpm;
  final ThresholdMode thresholdMode;

  /// Fade time for the base chase — overrides its own/its bank's per-step
  /// fade while this program is running.
  final Duration baseFade;

  final String? fasterChaseId;
  final String? fasterBankId;
  final String? fasterChaseLane;
  final double fasterThreshold; // % or BPM above baseBpm, per thresholdMode
  final Duration fasterHold;
  final Duration fasterFade;

  final String? slowerChaseId;
  final String? slowerBankId;
  final String? slowerChaseLane;
  final double slowerThreshold; // % or BPM below baseBpm, per thresholdMode
  final Duration slowerHold;
  final Duration slowerFade;

  /// How long the rig takes to fade out when the music stops. Deliberately
  /// its own (longer) setting rather than reusing a zone's fade — a show
  /// dying out should look like a sunset, not a step.
  final Duration blackoutFade;

  /// Every layer other than Layer 1 this program drives, each with its own
  /// three zone targets. Layer 1's targets stay in the fields above, where
  /// every project saved before layers existed already keeps them — so an
  /// old show loads as a Layer-1-only program, unchanged.
  final List<LayerZoneTargets> extraLayers;

  const SmartProgram({
    required this.id,
    required this.name,
    this.baseChaseId,
    this.baseBankId,
    this.baseChaseLane,
    this.baseBpm = 120,
    this.thresholdMode = ThresholdMode.percent,
    this.baseFade = const Duration(milliseconds: 300),
    this.fasterChaseId,
    this.fasterBankId,
    this.fasterChaseLane,
    this.fasterThreshold = 10,
    this.fasterHold = const Duration(seconds: 3),
    this.fasterFade = const Duration(milliseconds: 300),
    this.slowerChaseId,
    this.slowerBankId,
    this.slowerChaseLane,
    this.slowerThreshold = 10,
    this.slowerHold = const Duration(seconds: 3),
    this.slowerFade = const Duration(milliseconds: 300),
    this.blackoutFade = const Duration(seconds: 3),
    this.extraLayers = const [],
  });

  /// Layer 1's targets plus every extra layer's — one entry per layer, Layer
  /// 1 first, whether or not a layer has anything set.
  List<LayerZoneTargets> get layers => [
    LayerZoneTargets(layerId: layer1Id, base: baseTarget, faster: fasterTarget, slower: slowerTarget),
    for (final l in extraLayers)
      if (l.layerId != layer1Id) l,
  ];

  /// The layers this program actually plays something on.
  List<LayerZoneTargets> get drivenLayers => [for (final l in layers) if (!l.isEmpty) l];

  LayerZoneTargets targetsFor(String layerId) => layers.firstWhere(
    (l) => l.layerId == layerId,
    orElse: () => LayerZoneTargets(layerId: layerId),
  );

  bool get hasAnyTarget => drivenLayers.isNotEmpty;

  /// Whether any layer has its own Faster/Slower target — without one the
  /// program never leaves Base in that direction.
  bool get hasFasterTarget => layers.any((l) => l.faster != null);
  bool get hasSlowerTarget => layers.any((l) => l.slower != null);

  /// Whether any zone on any layer plays the chase [chaseId].
  bool usesChase(String chaseId) => layers.any(
    (l) => [l.base, l.faster, l.slower].any((t) => t != null && !t.isBank && t.id == chaseId),
  );

  /// This program with every layer's targets replaced by [all] — Layer 1's
  /// go back into the legacy fields, the rest into [extraLayers]; empty
  /// extra layers are dropped.
  SmartProgram withLayerTargets(List<LayerZoneTargets> all) {
    final l1 = all.firstWhere((l) => l.layerId == layer1Id, orElse: () => const LayerZoneTargets(layerId: layer1Id));
    return SmartProgram(
      id: id,
      name: name,
      baseChaseId: l1.base?.chaseId,
      baseBankId: l1.base?.bankId,
      baseChaseLane: l1.base?.chaseLane,
      baseBpm: baseBpm,
      thresholdMode: thresholdMode,
      baseFade: baseFade,
      fasterChaseId: l1.faster?.chaseId,
      fasterBankId: l1.faster?.bankId,
      fasterChaseLane: l1.faster?.chaseLane,
      fasterThreshold: fasterThreshold,
      fasterHold: fasterHold,
      fasterFade: fasterFade,
      slowerChaseId: l1.slower?.chaseId,
      slowerBankId: l1.slower?.bankId,
      slowerChaseLane: l1.slower?.chaseLane,
      slowerThreshold: slowerThreshold,
      slowerHold: slowerHold,
      slowerFade: slowerFade,
      blackoutFade: blackoutFade,
      extraLayers: [for (final l in all) if (l.layerId != layer1Id && !l.isEmpty) l],
    );
  }

  /// A full copy under a new [newId] and [newName].
  SmartProgram duplicateAs(String newId, String newName) => SmartProgram(
    id: newId,
    name: newName,
    baseChaseId: baseChaseId,
    baseBankId: baseBankId,
    baseChaseLane: baseChaseLane,
    baseBpm: baseBpm,
    thresholdMode: thresholdMode,
    baseFade: baseFade,
    fasterChaseId: fasterChaseId,
    fasterBankId: fasterBankId,
    fasterChaseLane: fasterChaseLane,
    fasterThreshold: fasterThreshold,
    fasterHold: fasterHold,
    fasterFade: fasterFade,
    slowerChaseId: slowerChaseId,
    slowerBankId: slowerBankId,
    slowerChaseLane: slowerChaseLane,
    slowerThreshold: slowerThreshold,
    slowerHold: slowerHold,
    slowerFade: slowerFade,
    blackoutFade: blackoutFade,
    extraLayers: extraLayers,
  );

  /// The BPM at/above which the "faster" chase should take over.
  double get fasterTriggerBpm =>
      thresholdMode == ThresholdMode.percent ? baseBpm * (1 + fasterThreshold / 100) : baseBpm + fasterThreshold;

  /// The BPM at/below which the "slower" chase should take over.
  double get slowerTriggerBpm =>
      thresholdMode == ThresholdMode.percent ? baseBpm * (1 - slowerThreshold / 100) : baseBpm - slowerThreshold;

  ProgramTarget? get baseTarget => ProgramTarget.from(chaseId: baseChaseId, bankId: baseBankId, chaseLane: baseChaseLane);
  ProgramTarget? get fasterTarget => ProgramTarget.from(chaseId: fasterChaseId, bankId: fasterBankId, chaseLane: fasterChaseLane);
  ProgramTarget? get slowerTarget => ProgramTarget.from(chaseId: slowerChaseId, bankId: slowerBankId, chaseLane: slowerChaseLane);

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
      baseChaseLane: clearBase || baseChaseId != null ? null : baseChaseLane,
      baseBpm: baseBpm ?? this.baseBpm,
      thresholdMode: thresholdMode ?? this.thresholdMode,
      baseFade: baseFade ?? this.baseFade,
      fasterChaseId: clearFaster ? fasterChaseId : (fasterChaseId ?? this.fasterChaseId),
      fasterBankId: clearFaster ? fasterBankId : (fasterBankId ?? this.fasterBankId),
      fasterChaseLane: clearFaster || fasterChaseId != null ? null : fasterChaseLane,
      fasterThreshold: fasterThreshold ?? this.fasterThreshold,
      fasterHold: fasterHold ?? this.fasterHold,
      fasterFade: fasterFade ?? this.fasterFade,
      slowerChaseId: clearSlower ? slowerChaseId : (slowerChaseId ?? this.slowerChaseId),
      slowerBankId: clearSlower ? slowerBankId : (slowerBankId ?? this.slowerBankId),
      slowerChaseLane: clearSlower || slowerChaseId != null ? null : slowerChaseLane,
      slowerThreshold: slowerThreshold ?? this.slowerThreshold,
      slowerHold: slowerHold ?? this.slowerHold,
      slowerFade: slowerFade ?? this.slowerFade,
      blackoutFade: blackoutFade ?? this.blackoutFade,
      extraLayers: extraLayers,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseChaseId': baseChaseId,
    'baseBankId': baseBankId,
    if (baseChaseLane != null) 'baseChaseLane': baseChaseLane,
    'baseBpm': baseBpm,
    'thresholdMode': thresholdMode.name,
    'baseFadeMs': baseFade.inMilliseconds,
    'fasterChaseId': fasterChaseId,
    'fasterBankId': fasterBankId,
    if (fasterChaseLane != null) 'fasterChaseLane': fasterChaseLane,
    'fasterThreshold': fasterThreshold,
    'fasterHoldMs': fasterHold.inMilliseconds,
    'fasterFadeMs': fasterFade.inMilliseconds,
    'slowerChaseId': slowerChaseId,
    'slowerBankId': slowerBankId,
    if (slowerChaseLane != null) 'slowerChaseLane': slowerChaseLane,
    'slowerThreshold': slowerThreshold,
    'slowerHoldMs': slowerHold.inMilliseconds,
    'slowerFadeMs': slowerFade.inMilliseconds,
    'blackoutFadeMs': blackoutFade.inMilliseconds,
    if (extraLayers.isNotEmpty) 'extraLayers': extraLayers.map((l) => l.toJson()).toList(),
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
      baseChaseLane: json['baseChaseLane'] as String?,
      baseBpm: (json['baseBpm'] as num?)?.toDouble() ?? 120,
      thresholdMode: ThresholdMode.values.firstWhere(
        (m) => m.name == json['thresholdMode'],
        orElse: () => ThresholdMode.percent,
      ),
      baseFade: Duration(milliseconds: json['baseFadeMs'] as int? ?? legacyFadeMs),
      fasterChaseId: json['fasterChaseId'] as String?,
      fasterBankId: json['fasterBankId'] as String?,
      fasterChaseLane: json['fasterChaseLane'] as String?,
      fasterThreshold: (json['fasterThreshold'] as num?)?.toDouble() ?? 10,
      fasterHold: Duration(milliseconds: json['fasterHoldMs'] as int? ?? 3000),
      fasterFade: Duration(milliseconds: json['fasterFadeMs'] as int? ?? legacyFadeMs),
      slowerChaseId: json['slowerChaseId'] as String?,
      slowerBankId: json['slowerBankId'] as String?,
      slowerChaseLane: json['slowerChaseLane'] as String?,
      slowerThreshold: (json['slowerThreshold'] as num?)?.toDouble() ?? 10,
      slowerHold: Duration(milliseconds: json['slowerHoldMs'] as int? ?? 3000),
      slowerFade: Duration(milliseconds: json['slowerFadeMs'] as int? ?? legacyFadeMs),
      blackoutFade: Duration(milliseconds: json['blackoutFadeMs'] as int? ?? 3000),
      extraLayers: (json['extraLayers'] as List? ?? [])
          .map((l) => LayerZoneTargets.fromJson(l as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// What one Smart Program zone plays: a saved chase, or a whole bank.
class ProgramTarget {
  final String id;
  final bool isBank;

  /// For a chase: play only the steps it puts on this layer (one "lane" of
  /// a multi-layer chase), rather than all of them. Null plays the whole
  /// chase. This is what splitting a two-layer chase across a zone's layers
  /// leaves on each of them.
  final String? lane;

  const ProgramTarget({required this.id, required this.isBank, this.lane});

  String? get chaseId => isBank ? null : id;
  String? get bankId => isBank ? id : null;
  String? get chaseLane => isBank ? null : lane;

  static ProgramTarget? from({String? chaseId, String? bankId, String? chaseLane}) {
    if (chaseId != null) return ProgramTarget(id: chaseId, isBank: false, lane: chaseLane);
    if (bankId != null) return ProgramTarget(id: bankId, isBank: true);
    return null;
  }

  // Compared by value: the getters build a fresh instance every call, so
  // the player's "did the target actually change?" check would otherwise
  // see a difference on every edit and restart the chase needlessly.
  @override
  bool operator ==(Object other) =>
      other is ProgramTarget && other.id == id && other.isBank == isBank && other.lane == lane;

  @override
  int get hashCode => Object.hash(id, isBank, lane);
}
