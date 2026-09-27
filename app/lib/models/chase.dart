enum ChaseDirection { forward, bounce, random }

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

  const Chase({
    required this.id,
    required this.name,
    required this.steps,
    this.stepSeconds = 1.0,
    this.beatSync = false,
    this.direction = ChaseDirection.forward,
  });

  Chase copyWith({
    String? name,
    List<ChaseStep>? steps,
    double? stepSeconds,
    bool? beatSync,
    ChaseDirection? direction,
  }) {
    return Chase(
      id: id,
      name: name ?? this.name,
      steps: steps ?? this.steps,
      stepSeconds: stepSeconds ?? this.stepSeconds,
      beatSync: beatSync ?? this.beatSync,
      direction: direction ?? this.direction,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'steps': steps.map((s) => s.toJson()).toList(),
    'stepSeconds': stepSeconds,
    'beatSync': beatSync,
    'direction': direction.name,
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
    );
  }
}
