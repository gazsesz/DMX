import 'group_position.dart';
import 'pan_tilt.dart';

/// The path a moving head's beam draws, before size, rotation and speed.
enum MovementShape {
  /// Round and round.
  circle,

  /// Left and right along a sine — slows at both ends.
  panSweep,

  /// Up and down along a sine.
  tiltSweep,

  /// Left and right at constant speed, turning sharply at the ends.
  sweep,

  /// Figure of eight: tilt runs at twice the rate of the pan swing.
  swim,

  /// Wanders: detuned sines on both axes, so it never repeats an obvious shape.
  float,

  /// A scanner bar: pan to and fro, easing in and out of each end.
  lightRider,

  /// Round the four corners of a square.
  square,

  /// Round the four corners of a diamond.
  diamond,

  /// Wanders smoothly between random spots, a new set for every head that
  /// has its own place in the wave.
  random,

  /// Jumps from random spot to random spot, holding each for a while.
  randomJump,

  /// Stays put at the centre of the path (size does nothing).
  hold;

  String get label => switch (this) {
    MovementShape.circle => 'Circle',
    MovementShape.panSweep => 'Pan sweep',
    MovementShape.tiltSweep => 'Tilt sweep',
    MovementShape.sweep => 'Sweep',
    MovementShape.swim => 'Swim',
    MovementShape.float => 'Float',
    MovementShape.lightRider => 'Light rider',
    MovementShape.square => 'Square',
    MovementShape.diamond => 'Diamond',
    MovementShape.random => 'Random',
    MovementShape.randomJump => 'Random jumps',
    MovementShape.hold => 'Hold',
  };

  static MovementShape parse(dynamic name) =>
      MovementShape.values.firstWhere((s) => s.name == name, orElse: () => MovementShape.circle);
}

/// Where the path is drawn: straight in pan/tilt, or on the stage plan.
enum MovementSpace {
  /// Size is an angle each head sweeps through, round its own centre pan/tilt.
  panTilt,

  /// Size is metres on the stage plan; every head aims at its own point on
  /// the path, so the shape is the same on the floor whatever the rigging.
  stage;

  String get label => switch (this) {
    MovementSpace.panTilt => 'Pan / tilt',
    MovementSpace.stage => 'Stage plan',
  };

  static MovementSpace parse(dynamic name) =>
      MovementSpace.values.firstWhere((s) => s.name == name, orElse: () => MovementSpace.panTilt);
}

/// A movement effect: a path and how it is run, played live by the chase
/// player instead of being baked into scenes. It lives on a [Bank] (the
/// bank then has no scene slots), so a chase or a Smart Program uses it
/// like any other bank.
class MovementFx {
  final MovementShape shape;
  final MovementSpace space;

  /// Pan/tilt space: half the swing each way, in degrees of the head's own
  /// travel.
  final double sizePanDeg;
  final double sizeTiltDeg;

  /// Pan/tilt space: the middle of the path.
  final PanTilt center;

  /// Stage space: the middle of the path on the plan, half the width and
  /// depth of the path in metres, and the height of the plane it is drawn on.
  final StagePoint stageCenter;
  final double sizeXM;
  final double sizeYM;
  final double aimHeightM;

  /// Turns the whole path round its centre, in degrees.
  final double rotationDeg;

  /// How long one lap takes when not locked to the beat.
  final double periodSec;

  /// Locks the lap to the music: one lap every [beats] beats.
  final bool beatLocked;
  final double beats;

  /// Runs the path backwards.
  final bool reverse;

  /// How far round the path the last head is from the first, as a fraction
  /// of a lap — 0 moves them as one, 1 spreads them evenly round a full lap.
  final double phaseSpread;

  /// Heads right of the stage centre swing the opposite way in pan.
  final bool mirror;

  /// Spreads the heads out round the path: each head is this much further
  /// along than the one before, centred on the group — degrees of pan in
  /// pan/tilt space, metres across the stage in stage space.
  final double fanPanDeg;
  final double fanXM;

  /// Who moves. Both empty means every head with pan and tilt.
  final Set<String> groupIds;
  final Set<String> fixtureIds;

  /// A scene bank played alongside the path — the colours, gobo, dimmer… that
  /// go with the movement. Its pan/tilt is ignored for the heads the path
  /// drives. Null for none.
  final String? lookBankId;

  /// The look steps at its own [lookHoldMs]/[lookFadeMs] instead of the
  /// dock's Hold/Fade (and beat sync, which only the dock's timing follows).
  final bool lookOwnTiming;
  final int lookHoldMs;
  final int lookFadeMs;

  static const periodRange = (min: 0.5, max: 60.0);
  static const beatChoices = [0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 32.0];

  const MovementFx({
    this.shape = MovementShape.circle,
    this.space = MovementSpace.panTilt,
    this.sizePanDeg = 40,
    this.sizeTiltDeg = 30,
    this.center = PanTilt.center,
    this.stageCenter = const StagePoint(0.5, 0.5),
    this.sizeXM = 2,
    this.sizeYM = 1.5,
    this.aimHeightM = 0,
    this.rotationDeg = 0,
    this.periodSec = 4,
    this.beatLocked = false,
    this.beats = 4,
    this.reverse = false,
    this.phaseSpread = 0,
    this.mirror = false,
    this.fanPanDeg = 0,
    this.fanXM = 0,
    this.groupIds = const {},
    this.fixtureIds = const {},
    this.lookBankId,
    this.lookOwnTiming = false,
    this.lookHoldMs = 1200,
    this.lookFadeMs = 300,
  });

  /// One-tap starting points for the Banks screen.
  factory MovementFx.preset(MovementShape shape) => switch (shape) {
    MovementShape.circle => const MovementFx(shape: MovementShape.circle, sizePanDeg: 35, sizeTiltDeg: 35),
    MovementShape.swim => const MovementFx(shape: MovementShape.swim, periodSec: 6, phaseSpread: 0.5),
    MovementShape.float => const MovementFx(shape: MovementShape.float, periodSec: 12, phaseSpread: 1),
    MovementShape.random => const MovementFx(shape: MovementShape.random, periodSec: 16, phaseSpread: 1),
    MovementShape.randomJump => const MovementFx(shape: MovementShape.randomJump, beatLocked: true, beats: 4, phaseSpread: 1),
    MovementShape.hold => const MovementFx(shape: MovementShape.hold, sizePanDeg: 0, sizeTiltDeg: 0),
    MovementShape.lightRider => const MovementFx(
      shape: MovementShape.lightRider,
      sizePanDeg: 60,
      sizeTiltDeg: 0,
      periodSec: 3,
    ),
    MovementShape.panSweep => const MovementFx(shape: MovementShape.panSweep, sizePanDeg: 60, sizeTiltDeg: 0),
    _ => MovementFx(shape: shape),
  };

  MovementFx copyWith({
    MovementShape? shape,
    MovementSpace? space,
    double? sizePanDeg,
    double? sizeTiltDeg,
    PanTilt? center,
    StagePoint? stageCenter,
    double? sizeXM,
    double? sizeYM,
    double? aimHeightM,
    double? rotationDeg,
    double? periodSec,
    bool? beatLocked,
    double? beats,
    bool? reverse,
    double? phaseSpread,
    bool? mirror,
    double? fanPanDeg,
    double? fanXM,
    Set<String>? groupIds,
    Set<String>? fixtureIds,
    String? lookBankId,
    bool clearLook = false,
    bool? lookOwnTiming,
    int? lookHoldMs,
    int? lookFadeMs,
  }) {
    return MovementFx(
      shape: shape ?? this.shape,
      space: space ?? this.space,
      sizePanDeg: sizePanDeg ?? this.sizePanDeg,
      sizeTiltDeg: sizeTiltDeg ?? this.sizeTiltDeg,
      center: center ?? this.center,
      stageCenter: stageCenter ?? this.stageCenter,
      sizeXM: sizeXM ?? this.sizeXM,
      sizeYM: sizeYM ?? this.sizeYM,
      aimHeightM: aimHeightM ?? this.aimHeightM,
      rotationDeg: rotationDeg ?? this.rotationDeg,
      periodSec: periodSec ?? this.periodSec,
      beatLocked: beatLocked ?? this.beatLocked,
      beats: beats ?? this.beats,
      reverse: reverse ?? this.reverse,
      phaseSpread: phaseSpread ?? this.phaseSpread,
      mirror: mirror ?? this.mirror,
      fanPanDeg: fanPanDeg ?? this.fanPanDeg,
      fanXM: fanXM ?? this.fanXM,
      groupIds: groupIds ?? this.groupIds,
      fixtureIds: fixtureIds ?? this.fixtureIds,
      lookBankId: clearLook ? null : (lookBankId ?? this.lookBankId),
      lookOwnTiming: lookOwnTiming ?? this.lookOwnTiming,
      lookHoldMs: lookHoldMs ?? this.lookHoldMs,
      lookFadeMs: lookFadeMs ?? this.lookFadeMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'shape': shape.name,
    'space': space.name,
    'sizePanDeg': sizePanDeg,
    'sizeTiltDeg': sizeTiltDeg,
    'center': center.toJson(),
    'stageCenter': stageCenter.toJson(),
    'sizeXM': sizeXM,
    'sizeYM': sizeYM,
    'aimHeightM': aimHeightM,
    'rotationDeg': rotationDeg,
    'periodSec': periodSec,
    'beatLocked': beatLocked,
    'beats': beats,
    'reverse': reverse,
    'phaseSpread': phaseSpread,
    'mirror': mirror,
    if (fanPanDeg != 0) 'fanPanDeg': fanPanDeg,
    if (fanXM != 0) 'fanXM': fanXM,
    if (groupIds.isNotEmpty) 'groupIds': groupIds.toList(),
    if (fixtureIds.isNotEmpty) 'fixtureIds': fixtureIds.toList(),
    if (lookBankId != null) 'lookBankId': lookBankId,
    if (lookOwnTiming) 'lookOwnTiming': true,
    if (lookOwnTiming) 'lookHoldMs': lookHoldMs,
    if (lookOwnTiming) 'lookFadeMs': lookFadeMs,
  };

  static MovementFx? fromJson(dynamic json) {
    if (json is! Map) return null;
    double number(String key, double fallback, double min, double max) =>
        ((json[key] as num?)?.toDouble() ?? fallback).clamp(min, max);
    Set<String> ids(String key) => {for (final id in json[key] as List? ?? const []) id as String};
    return MovementFx(
      shape: MovementShape.parse(json['shape']),
      space: MovementSpace.parse(json['space']),
      sizePanDeg: number('sizePanDeg', 40, 0, 270),
      sizeTiltDeg: number('sizeTiltDeg', 30, 0, 135),
      center: PanTilt.fromJson(json['center']) ?? PanTilt.center,
      stageCenter: StagePoint.fromJson(json['stageCenter']) ?? const StagePoint(0.5, 0.5),
      sizeXM: number('sizeXM', 2, 0, 100),
      sizeYM: number('sizeYM', 1.5, 0, 100),
      aimHeightM: number('aimHeightM', 0, 0, 50),
      rotationDeg: number('rotationDeg', 0, -360, 360),
      periodSec: number('periodSec', 4, periodRange.min, periodRange.max),
      beatLocked: json['beatLocked'] == true,
      beats: number('beats', 4, 0.25, 64),
      reverse: json['reverse'] == true,
      phaseSpread: number('phaseSpread', 0, 0, 1),
      mirror: json['mirror'] == true,
      fanPanDeg: number('fanPanDeg', 0, 0, 90),
      fanXM: number('fanXM', 0, 0, 5),
      groupIds: ids('groupIds'),
      fixtureIds: ids('fixtureIds'),
      lookBankId: json['lookBankId'] as String?,
      lookOwnTiming: json['lookOwnTiming'] == true,
      lookHoldMs: number('lookHoldMs', 1200, 20, 60000).round(),
      lookFadeMs: number('lookFadeMs', 300, 0, 120000).round(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MovementFx && _sameJson(other.toJson(), toJson());

  @override
  int get hashCode => Object.hashAll(toJson().values.map((v) => v is List ? Object.hashAll(v) : v));
}

bool _sameJson(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    final x = a[key];
    final y = b[key];
    if (x is List && y is List) {
      if (x.length != y.length) return false;
      for (var i = 0; i < x.length; i++) {
        if (x[i] != y[i]) return false;
      }
    } else if (x != y) {
      return false;
    }
  }
  return true;
}

/// The live knobs laid over whatever Movement FX is running — what the
/// Movement strip and the remote's `/fx` endpoint set. They multiply or add
/// to the bank's own settings and never change the bank, so the bank is
/// still what you built when the knobs go back to neutral.
class MovementLive {
  /// Scales how far the path swings (every size field). 1 is the bank's own.
  final double size;

  /// Scales the pace, 1 is the bank's own: 2 laps twice as fast.
  final double speed;

  /// Added to the bank's wave across heads, as a fraction of a lap.
  final double shift;

  /// Rounds the move off: how long, 0..1 of 1.5 s, the heads take to catch up
  /// with where the path says they should be. Softens sharp turns and turns
  /// jumps into glides.
  final double smooth;

  const MovementLive({this.size = 1, this.speed = 1, this.shift = 0, this.smooth = 0});

  static const neutral = MovementLive();
  static const sizeRange = (min: 0.0, max: 2.0);
  static const speedRange = (min: 0.25, max: 4.0);

  bool get isNeutral => this == neutral;

  /// How long the heads take to catch up with the path.
  Duration get smoothing => Duration(milliseconds: (smooth.clamp(0.0, 1.0) * 1500).round());

  MovementLive copyWith({double? size, double? speed, double? shift, double? smooth}) => MovementLive(
    size: (size ?? this.size).clamp(sizeRange.min, sizeRange.max),
    speed: (speed ?? this.speed).clamp(speedRange.min, speedRange.max),
    shift: (shift ?? this.shift).clamp(0.0, 1.0),
    smooth: (smooth ?? this.smooth).clamp(0.0, 1.0),
  );

  /// [fx] with the size and shift knobs applied (speed and smoothing act on
  /// the clock and on the output, not on the path).
  MovementFx applyTo(MovementFx fx) {
    if (size == 1 && shift == 0) return fx;
    return fx.copyWith(
      sizePanDeg: fx.sizePanDeg * size,
      sizeTiltDeg: fx.sizeTiltDeg * size,
      sizeXM: fx.sizeXM * size,
      sizeYM: fx.sizeYM * size,
      phaseSpread: (fx.phaseSpread + shift).clamp(0.0, 1.0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MovementLive &&
      other.size == size &&
      other.speed == speed &&
      other.shift == shift &&
      other.smooth == smooth;

  @override
  int get hashCode => Object.hash(size, speed, shift, smooth);
}
