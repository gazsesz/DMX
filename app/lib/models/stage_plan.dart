/// A named spot on (or above) the stage the movers can be aimed at — a
/// mirror ball, the DJ booth, a podium.
class AimTarget {
  final String id;
  final String name;

  /// Position on the stage plan, normalised like a fixture's layout: x stage
  /// left to right, y upstage (0) to the audience edge (1).
  final double x;
  final double y;

  /// Height above the floor, in metres.
  final double heightM;

  const AimTarget({required this.id, required this.name, required this.x, required this.y, this.heightM = 0});

  AimTarget copyWith({String? name, double? x, double? y, double? heightM}) {
    return AimTarget(
      id: id,
      name: name ?? this.name,
      x: x ?? this.x,
      y: y ?? this.y,
      heightM: heightM ?? this.heightM,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'x': x, 'y': y, 'heightM': heightM};

  factory AimTarget.fromJson(Map<String, dynamic> json) {
    double number(String key, double fallback) => (json[key] as num?)?.toDouble() ?? fallback;
    return AimTarget(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Target',
      x: number('x', 0.5).clamp(0.0, 1.0),
      y: number('y', 0.5).clamp(0.0, 1.0),
      heightM: number('heightM', 0).clamp(0.0, 50.0),
    );
  }
}

/// The real-world size of the 2D stage layout, so a spot on the plan can be
/// turned into metres for aiming, plus the named spots worth aiming at.
class StagePlan {
  /// Width (stage left to right) and depth (upstage to the audience edge)
  /// the layout canvas stands for, in metres.
  final double widthM;
  final double depthM;
  final List<AimTarget> targets;

  static const defaultWidthM = 8.0;
  static const defaultDepthM = 6.0;

  const StagePlan({this.widthM = defaultWidthM, this.depthM = defaultDepthM, this.targets = const []});

  StagePlan copyWith({double? widthM, double? depthM, List<AimTarget>? targets}) {
    return StagePlan(
      widthM: widthM ?? this.widthM,
      depthM: depthM ?? this.depthM,
      targets: targets ?? this.targets,
    );
  }

  Map<String, dynamic> toJson() => {
    'widthM': widthM,
    'depthM': depthM,
    'targets': [for (final t in targets) t.toJson()],
  };

  factory StagePlan.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const StagePlan();
    double size(String key, double fallback) {
      final value = (json[key] as num?)?.toDouble();
      return value == null || value <= 0 ? fallback : value.clamp(1.0, 200.0);
    }

    return StagePlan(
      widthM: size('widthM', defaultWidthM),
      depthM: size('depthM', defaultDepthM),
      targets: [
        for (final t in json['targets'] as List? ?? const []) AimTarget.fromJson(t as Map<String, dynamic>),
      ],
    );
  }
}
