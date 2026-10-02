/// Which way up a moving head is rigged. It decides which way "tilt" lifts
/// the beam and, because a hung head is upside down, which way pan turns.
enum MountKind {
  /// Clamped to a truss or a ceiling, base up — the usual club rig.
  hanging,

  /// Sitting on the floor or a riser, base down.
  standing;

  String get label => switch (this) {
    MountKind.hanging => 'Hanging',
    MountKind.standing => 'Standing',
  };
}

/// How one patched moving head is physically rigged — the half of aiming
/// that the fixture's profile can't know.
///
/// Only the stage-aim view needs this; the position pad works straight in
/// pan/tilt and ignores it. Every field has a sensible default, so a show
/// that never opens the stage view never has to fill it in.
class FixtureMounting {
  final MountKind mount;

  /// The head's height above the floor, in metres — the truss trim for a
  /// hung head, the riser for a standing one.
  final double heightM;

  /// Where the beam points on the stage plan when pan sits at the middle of
  /// its range, in degrees: 0 = towards the audience (down the plan), 90 =
  /// towards stage-plan right, 180 = upstage, 270 = left.
  final double facingDeg;

  /// For a head that's rigged mirrored, so the same direction on the pad
  /// turns it the opposite way.
  final bool invertPan;
  final bool invertTilt;

  /// What calibration measured: the difference between where the maths said
  /// the beam would land and where it actually did, in degrees. Added to
  /// every aimed position, which also soaks up a tape-measure error in
  /// [heightM] or a head clamped a few degrees off [facingDeg].
  final double panOffsetDeg;
  final double tiltOffsetDeg;

  static const defaultHangingHeightM = 3.0;
  static const defaultStandingHeightM = 0.4;

  const FixtureMounting({
    this.mount = MountKind.hanging,
    this.heightM = defaultHangingHeightM,
    this.facingDeg = 0,
    this.invertPan = false,
    this.invertTilt = false,
    this.panOffsetDeg = 0,
    this.tiltOffsetDeg = 0,
  });

  bool get isCalibrated => panOffsetDeg != 0 || tiltOffsetDeg != 0;

  bool get isDefault =>
      mount == MountKind.hanging &&
      heightM == defaultHangingHeightM &&
      facingDeg == 0 &&
      !invertPan &&
      !invertTilt &&
      !isCalibrated;

  FixtureMounting copyWith({
    MountKind? mount,
    double? heightM,
    double? facingDeg,
    bool? invertPan,
    bool? invertTilt,
    double? panOffsetDeg,
    double? tiltOffsetDeg,
  }) {
    return FixtureMounting(
      mount: mount ?? this.mount,
      heightM: heightM ?? this.heightM,
      facingDeg: facingDeg ?? this.facingDeg,
      invertPan: invertPan ?? this.invertPan,
      invertTilt: invertTilt ?? this.invertTilt,
      panOffsetDeg: panOffsetDeg ?? this.panOffsetDeg,
      tiltOffsetDeg: tiltOffsetDeg ?? this.tiltOffsetDeg,
    );
  }

  Map<String, dynamic> toJson() => {
    'mount': mount.name,
    'heightM': heightM,
    'facingDeg': facingDeg,
    if (invertPan) 'invertPan': true,
    if (invertTilt) 'invertTilt': true,
    if (panOffsetDeg != 0) 'panOffsetDeg': panOffsetDeg,
    if (tiltOffsetDeg != 0) 'tiltOffsetDeg': tiltOffsetDeg,
  };

  factory FixtureMounting.fromJson(Map<String, dynamic> json) {
    double number(String key, double fallback) => (json[key] as num?)?.toDouble() ?? fallback;
    return FixtureMounting(
      mount: MountKind.values.firstWhere((m) => m.name == json['mount'], orElse: () => MountKind.hanging),
      heightM: number('heightM', defaultHangingHeightM).clamp(0.0, 50.0),
      facingDeg: number('facingDeg', 0) % 360,
      invertPan: json['invertPan'] == true,
      invertTilt: json['invertTilt'] == true,
      panOffsetDeg: number('panOffsetDeg', 0),
      tiltOffsetDeg: number('tiltOffsetDeg', 0),
    );
  }
}
