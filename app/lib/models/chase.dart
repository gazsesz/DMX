enum ChaseDirection { forward, bounce, random }

/// How one layer of a chase (a lane) is clocked, independent of the others.
enum LaneTiming {
  /// Follows the dock: beat sync switch, Override timing and Auto-Fade.
  followApp,

  /// Steps on the beat whenever beats are coming in, even with the dock's
  /// Beat Sync off.
  onBeat,

  /// Runs on its own steps' Hold/Fade only — never waits for a beat and
  /// ignores the dock's Override timing and Auto-Fade. For slow moves.
  free;

  String get label => switch (this) {
    LaneTiming.followApp => 'Follow dock',
    LaneTiming.onBeat => 'On beat',
    LaneTiming.free => 'Free-running',
  };
}

/// One step of a chase: either a single scene or a whole bank (played as
/// its own mini-sequence of filled slots).
class ChaseStep {
  final String? sceneId;
  final String? bankId;
  final Duration hold;
  final Duration fade;

  /// Which layer this step plays on. Null means Layer 1 — the default, so
  /// a chase only has to say anything for the steps meant elsewhere. Steps
  /// sharing a layer form one lane; lanes play side by side (see
  /// `chaseLanes`).
  final String? layerId;

  const ChaseStep({
    this.sceneId,
    this.bankId,
    this.hold = const Duration(milliseconds: 800),
    this.fade = const Duration(milliseconds: 300),
    this.layerId,
  });

  /// [clearLayer] puts the step back on the default layer.
  ChaseStep copyWith({Duration? hold, Duration? fade, String? layerId, bool clearLayer = false}) {
    return ChaseStep(
      sceneId: sceneId,
      bankId: bankId,
      hold: hold ?? this.hold,
      fade: fade ?? this.fade,
      layerId: clearLayer ? null : (layerId ?? this.layerId),
    );
  }

  Map<String, dynamic> toJson() => {
    'sceneId': sceneId,
    'bankId': bankId,
    'holdMs': hold.inMilliseconds,
    'fadeMs': fade.inMilliseconds,
    if (layerId != null) 'layerId': layerId,
  };

  factory ChaseStep.fromJson(Map<String, dynamic> json) {
    return ChaseStep(
      sceneId: json['sceneId'] as String?,
      bankId: json['bankId'] as String?,
      hold: Duration(milliseconds: json['holdMs'] as int? ?? 800),
      fade: Duration(milliseconds: json['fadeMs'] as int? ?? 300),
      layerId: json['layerId'] as String?,
    );
  }
}

class Chase {
  final String id;
  final String name;
  final List<ChaseStep> steps;
  final double stepSeconds;
  final bool beatSync;
  final ChaseDirection direction;

  /// Per-layer clocking, by layer id (Layer 1 is `layer1Id`). A layer not
  /// listed follows the dock.
  final Map<String, LaneTiming> laneTimings;

  LaneTiming timingOfLane(String layerId) => laneTimings[layerId] ?? LaneTiming.followApp;

  const Chase({
    required this.id,
    required this.name,
    required this.steps,
    this.stepSeconds = 1.0,
    this.beatSync = false,
    this.direction = ChaseDirection.forward,
    this.laneTimings = const {},
  });

  Chase copyWith({
    String? name,
    List<ChaseStep>? steps,
    double? stepSeconds,
    bool? beatSync,
    ChaseDirection? direction,
    Map<String, LaneTiming>? laneTimings,
  }) {
    return Chase(
      id: id,
      name: name ?? this.name,
      steps: steps ?? this.steps,
      stepSeconds: stepSeconds ?? this.stepSeconds,
      beatSync: beatSync ?? this.beatSync,
      direction: direction ?? this.direction,
      laneTimings: laneTimings ?? this.laneTimings,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'steps': steps.map((s) => s.toJson()).toList(),
    'stepSeconds': stepSeconds,
    'beatSync': beatSync,
    'direction': direction.name,
    if (laneTimings.isNotEmpty) 'laneTimings': {for (final e in laneTimings.entries) e.key: e.value.name},
  };

  factory Chase.fromJson(Map<String, dynamic> json) {
    return Chase(
      id: json['id'] as String,
      name: json['name'] as String,
      steps: (json['steps'] as List)
          .map((s) => ChaseStep.fromJson(s as Map<String, dynamic>))
          .toList(),
      stepSeconds: (json['stepSeconds'] as num?)?.toDouble() ?? 1.0,
      beatSync: json['beatSync'] as bool? ?? false,
      direction: ChaseDirection.values.firstWhere(
        (d) => d.name == json['direction'],
        orElse: () => ChaseDirection.forward,
      ),
      laneTimings: {
        for (final e in ((json['laneTimings'] as Map?) ?? const {}).entries)
          e.key as String: LaneTiming.values.firstWhere(
            (t) => t.name == e.value,
            orElse: () => LaneTiming.followApp,
          ),
      },
    );
  }
}
