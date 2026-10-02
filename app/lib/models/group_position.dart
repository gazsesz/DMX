import 'pan_tilt.dart';

/// How a Scene editor group's movers are being positioned.
enum PositionMode {
  /// Straight pan/tilt on the XY pad.
  pad,

  /// Aimed at spots on the stage plan; pan/tilt is worked out per head.
  stage,
}

/// How a group's beams are laid out around the stage-view handle.
enum StageFormation {
  /// Every beam on the same spot.
  point,

  /// Side by side across the stage, [GroupPosition.spreadM] apart.
  line,

  /// Evenly round a circle [GroupPosition.spreadM] across.
  circle;

  String get label => switch (this) {
    StageFormation.point => 'Single point',
    StageFormation.line => 'Line',
    StageFormation.circle => 'Circle',
  };
}

/// A spot on the stage plan, normalised like a fixture's layout position.
class StagePoint {
  final double x;
  final double y;

  const StagePoint(this.x, this.y);

  StagePoint clamped() => StagePoint(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));

  List<double> toJson() => [x, y];

  static StagePoint? fromJson(dynamic json) {
    if (json is! List || json.length < 2) return null;
    return StagePoint((json[0] as num).toDouble(), (json[1] as num).toDouble()).clamped();
  }

  @override
  bool operator ==(Object other) => other is StagePoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// Everything about a Scene editor group's position beyond the one shared
/// pan/tilt: the fan that spreads the heads apart, any head set on its own,
/// and, in stage mode, where on the plan the beams are aimed.
///
/// The scene itself only ever plays back the per-fixture DMX values this
/// resolves to. This is kept alongside them purely so reopening the scene
/// puts the pad, the fan and the crosshairs back where they were.
class GroupPosition {
  final PositionMode mode;

  /// The shared pan/tilt the pad's handle sits on. Saved with the scene
  /// because the scene's own values hold each head's fanned position, not
  /// the one they fan out from.
  final PanTilt? base;

  /// Degrees between neighbouring heads, stage left to right, centred on
  /// the shared position: a 4-head group at 10° sits at -15, -5, +5, +15.
  final double fanPanDeg;
  final double fanTiltDeg;

  /// Heads on the right half of the stage pan the mirror way, so a group
  /// hung left and right sweeps in and out symmetrically.
  final bool mirror;

  /// Heads positioned on their own (a recalled preset, or "Per fixture"),
  /// which then ignore the fan. Dragging the pad still moves them, by the
  /// same amount as the shared position, so the shape is kept.
  final Map<String, PanTilt> manual;

  /// Stage mode: the spot the group is aimed round, how the beams are laid
  /// out round it, and how high above the floor that spot is.
  final StagePoint handle;
  final StageFormation formation;
  final double spreadM;
  final double aimHeightM;

  /// Stage mode: beams dragged to a spot of their own.
  final Map<String, StagePoint> aimOverrides;

  static const defaultSpreadM = 1.5;
  static const defaultHandle = StagePoint(0.5, 0.75);

  const GroupPosition({
    this.mode = PositionMode.pad,
    this.base,
    this.fanPanDeg = 0,
    this.fanTiltDeg = 0,
    this.mirror = false,
    this.manual = const {},
    this.handle = defaultHandle,
    this.formation = StageFormation.line,
    this.spreadM = defaultSpreadM,
    this.aimHeightM = 0,
    this.aimOverrides = const {},
  });

  /// Nothing beyond a single shared pan/tilt. Such a group needs nothing
  /// saved, and older scenes reopen exactly as before.
  bool get isPlain => mode == PositionMode.pad && fanPanDeg == 0 && fanTiltDeg == 0 && !mirror && manual.isEmpty;

  GroupPosition copyWith({
    PositionMode? mode,
    PanTilt? base,
    double? fanPanDeg,
    double? fanTiltDeg,
    bool? mirror,
    Map<String, PanTilt>? manual,
    StagePoint? handle,
    StageFormation? formation,
    double? spreadM,
    double? aimHeightM,
    Map<String, StagePoint>? aimOverrides,
  }) {
    return GroupPosition(
      mode: mode ?? this.mode,
      base: base ?? this.base,
      fanPanDeg: fanPanDeg ?? this.fanPanDeg,
      fanTiltDeg: fanTiltDeg ?? this.fanTiltDeg,
      mirror: mirror ?? this.mirror,
      manual: manual ?? this.manual,
      handle: handle ?? this.handle,
      formation: formation ?? this.formation,
      spreadM: spreadM ?? this.spreadM,
      aimHeightM: aimHeightM ?? this.aimHeightM,
      aimOverrides: aimOverrides ?? this.aimOverrides,
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    if (base != null) 'base': base!.toJson(),
    if (fanPanDeg != 0) 'fanPanDeg': fanPanDeg,
    if (fanTiltDeg != 0) 'fanTiltDeg': fanTiltDeg,
    if (mirror) 'mirror': true,
    if (manual.isNotEmpty) 'manual': manual.map((id, p) => MapEntry(id, p.toJson())),
    if (mode == PositionMode.stage) ...{
      'handle': handle.toJson(),
      'formation': formation.name,
      'spreadM': spreadM,
      'aimHeightM': aimHeightM,
      if (aimOverrides.isNotEmpty) 'aimOverrides': aimOverrides.map((id, p) => MapEntry(id, p.toJson())),
    },
  };

  factory GroupPosition.fromJson(Map<String, dynamic> json) {
    double number(String key, double fallback) => (json[key] as num?)?.toDouble() ?? fallback;
    final rawManual = json['manual'] as Map<String, dynamic>? ?? const {};
    final rawOverrides = json['aimOverrides'] as Map<String, dynamic>? ?? const {};
    return GroupPosition(
      mode: PositionMode.values.firstWhere((m) => m.name == json['mode'], orElse: () => PositionMode.pad),
      base: PanTilt.fromJson(json['base']),
      fanPanDeg: number('fanPanDeg', 0),
      fanTiltDeg: number('fanTiltDeg', 0),
      mirror: json['mirror'] == true,
      manual: {
        for (final e in rawManual.entries)
          e.key: ?PanTilt.fromJson(e.value),
      },
      handle: StagePoint.fromJson(json['handle']) ?? defaultHandle,
      formation: StageFormation.values.firstWhere(
        (f) => f.name == json['formation'],
        orElse: () => StageFormation.line,
      ),
      spreadM: number('spreadM', defaultSpreadM).clamp(0.0, 50.0),
      aimHeightM: number('aimHeightM', 0).clamp(0.0, 50.0),
      aimOverrides: {
        for (final e in rawOverrides.entries)
          e.key: ?StagePoint.fromJson(e.value),
      },
    );
  }
}
