import 'movement_fx.dart';

/// What a Live Grid lane drives. Each effect kind owns one attribute group
/// of the fixtures it targets, so lanes never fight over a channel: a Moves
/// lane writes pan/tilt, Colors the colour mix and wheel, Level the dimmer,
/// Beam the gobo / strobe / zoom. A Show lane instead starts the project's
/// own Banks, Chases and Scenes on the regular players.
enum LiveLaneKind {
  moves,
  colors,
  level,
  beam,
  show;

  static LiveLaneKind parse(dynamic name) =>
      LiveLaneKind.values.firstWhere((k) => k.name == name, orElse: () => LiveLaneKind.colors);
}

/// Which fixtures a lane drives.
enum LiveTargetKind {
  /// Every fixture the lane's kind can drive.
  all,

  /// Fixtures with pan and tilt.
  heads,

  /// Fixtures with colour emitters but no pan/tilt — pars, bars, washes.
  pars,

  /// The fixture groups in [LiveLane.groupIds].
  groups;

  static LiveTargetKind parse(dynamic name) =>
      LiveTargetKind.values.firstWhere((k) => k.name == name, orElse: () => LiveTargetKind.all);
}

/// When a selected clip actually starts.
enum LiveQuantize {
  now,
  beat,
  bar;

  static LiveQuantize parse(dynamic name) =>
      LiveQuantize.values.firstWhere((k) => k.name == name, orElse: () => LiveQuantize.bar);
}

/// What tapping a clip does. Select + GO is the default: a tap only marks
/// the clip NEXT, GO switches every marked lane together.
enum LivePadMode {
  selectThenGo,
  launchDirectly;

  static LivePadMode parse(dynamic name) =>
      LivePadMode.values.firstWhere((k) => k.name == name, orElse: () => LivePadMode.selectThenGo);
}

/// The lane's speed against the clip's own timing: ¼ … ×4.
const liveLaneSpeeds = <double>[0.25, 0.5, 1, 2, 4];

class LiveLane {
  final String id;
  final String name;
  final LiveLaneKind kind;
  final LiveTargetKind target;
  final List<String> groupIds;

  /// Multiplies how fast every clip on this lane runs (one of [liveLaneSpeeds]).
  final double speed;

  /// Show lanes: the layer a Bank or Scene plays on (null = Layer 1). A
  /// Chase plays on the layers its own steps name.
  final String? layerId;

  const LiveLane({
    required this.id,
    required this.name,
    required this.kind,
    this.target = LiveTargetKind.all,
    this.groupIds = const [],
    this.speed = 1,
    this.layerId,
  });

  LiveLane copyWith({
    String? name,
    LiveLaneKind? kind,
    LiveTargetKind? target,
    List<String>? groupIds,
    double? speed,
    String? layerId,
  }) => LiveLane(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    target: target ?? this.target,
    groupIds: groupIds ?? this.groupIds,
    speed: speed ?? this.speed,
    layerId: layerId ?? this.layerId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'target': target.name,
    if (groupIds.isNotEmpty) 'groupIds': groupIds,
    if (speed != 1) 'speed': speed,
    if (layerId != null) 'layerId': layerId,
  };

  factory LiveLane.fromJson(Map<String, dynamic> json) => LiveLane(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    kind: LiveLaneKind.parse(json['kind']),
    target: LiveTargetKind.parse(json['target']),
    groupIds: [for (final g in json['groupIds'] as List? ?? const []) g as String],
    speed: (json['speed'] as num?)?.toDouble() ?? 1,
    layerId: json['layerId'] as String?,
  );
}

/// What a Show clip starts.
enum LiveShowKind {
  bank,
  chase,
  scene;

  static LiveShowKind parse(dynamic name) =>
      LiveShowKind.values.firstWhere((k) => k.name == name, orElse: () => LiveShowKind.bank);
}

/// A Show clip's target: one of the project's Banks, Chases or Scenes, by id.
class LiveShowRef {
  final LiveShowKind kind;
  final String id;

  const LiveShowRef({required this.kind, required this.id});

  Map<String, dynamic> toJson() => {'kind': kind.name, 'id': id};

  static LiveShowRef? fromJson(dynamic json) {
    if (json is! Map || json['id'] is! String) return null;
    return LiveShowRef(kind: LiveShowKind.parse(json['kind']), id: json['id'] as String);
  }

  @override
  bool operator ==(Object other) => other is LiveShowRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);
}

/// How a Colors clip moves through its colours.
enum LiveColorPattern {
  /// The first colour on every fixture.
  solid,

  /// Every fixture together, stepping through the colours.
  step,

  /// The colours spread across the fixtures and walk along them.
  chase,

  /// Neighbouring fixtures take alternate colours, swapping on the beat.
  alternate,

  /// A hue wheel turning across the fixtures (ignores the colour list).
  rainbow;

  static LiveColorPattern parse(dynamic name) =>
      LiveColorPattern.values.firstWhere((k) => k.name == name, orElse: () => LiveColorPattern.solid);
}

class LiveColorFx {
  final LiveColorPattern pattern;

  /// 0xRRGGBB values.
  final List<int> colors;

  /// Beats per colour step (or per full rainbow turn).
  final double beats;

  /// 0 = hard cut between colours, 1 = cross-fade the whole step.
  final double fade;

  const LiveColorFx({
    this.pattern = LiveColorPattern.solid,
    this.colors = const [0xFFFFFF],
    this.beats = 1,
    this.fade = 0,
  });

  LiveColorFx copyWith({LiveColorPattern? pattern, List<int>? colors, double? beats, double? fade}) => LiveColorFx(
    pattern: pattern ?? this.pattern,
    colors: colors ?? this.colors,
    beats: beats ?? this.beats,
    fade: fade ?? this.fade,
  );

  Map<String, dynamic> toJson() => {
    'pattern': pattern.name,
    'colors': [for (final c in colors) c.toRadixString(16).padLeft(6, '0')],
    'beats': beats,
    'fade': fade,
  };

  factory LiveColorFx.fromJson(Map<String, dynamic> json) => LiveColorFx(
    pattern: LiveColorPattern.parse(json['pattern']),
    colors: [
      for (final c in json['colors'] as List? ?? const [])
        if (int.tryParse(c.toString(), radix: 16) case final int v) v,
    ],
    beats: (json['beats'] as num?)?.toDouble() ?? 1,
    fade: (json['fade'] as num?)?.toDouble() ?? 0,
  );
}

/// How a Level clip shapes the dimmer.
enum LiveLevelPattern {
  /// Steady at [LiveLevelFx.high].
  solid,

  /// Smooth low → high → low over the cycle.
  breathe,

  /// High on the beat, decaying to low.
  pulse,

  /// One fixture at a time lit, walking along.
  chase,

  /// Rises low → high over the cycle, then drops.
  ramp;

  static LiveLevelPattern parse(dynamic name) =>
      LiveLevelPattern.values.firstWhere((k) => k.name == name, orElse: () => LiveLevelPattern.solid);
}

class LiveLevelFx {
  final LiveLevelPattern pattern;
  final double low;
  final double high;

  /// Beats per cycle.
  final double beats;

  /// 0 = every fixture in step, 1 = the cycle spread evenly across them.
  final double spread;

  const LiveLevelFx({
    this.pattern = LiveLevelPattern.solid,
    this.low = 0,
    this.high = 1,
    this.beats = 1,
    this.spread = 0,
  });

  LiveLevelFx copyWith({LiveLevelPattern? pattern, double? low, double? high, double? beats, double? spread}) =>
      LiveLevelFx(
        pattern: pattern ?? this.pattern,
        low: low ?? this.low,
        high: high ?? this.high,
        beats: beats ?? this.beats,
        spread: spread ?? this.spread,
      );

  Map<String, dynamic> toJson() => {
    'pattern': pattern.name,
    'low': low,
    'high': high,
    'beats': beats,
    'spread': spread,
  };

  factory LiveLevelFx.fromJson(Map<String, dynamic> json) => LiveLevelFx(
    pattern: LiveLevelPattern.parse(json['pattern']),
    low: (json['low'] as num?)?.toDouble() ?? 0,
    high: (json['high'] as num?)?.toDouble() ?? 1,
    beats: (json['beats'] as num?)?.toDouble() ?? 1,
    spread: (json['spread'] as num?)?.toDouble() ?? 0,
  );
}

/// Beam settings. Each value is 0..1 of that channel's range, or null to
/// leave the channel alone. Gobo is a raw DMX value because wheel slots are
/// picked from the fixture's own list.
class LiveBeamFx {
  final int? gobo;
  final double? strobe;
  final double? zoom;
  final double? goboRotation;

  const LiveBeamFx({this.gobo, this.strobe, this.zoom, this.goboRotation});

  LiveBeamFx copyWith({
    int? Function()? gobo,
    double? Function()? strobe,
    double? Function()? zoom,
    double? Function()? goboRotation,
  }) => LiveBeamFx(
    gobo: gobo != null ? gobo() : this.gobo,
    strobe: strobe != null ? strobe() : this.strobe,
    zoom: zoom != null ? zoom() : this.zoom,
    goboRotation: goboRotation != null ? goboRotation() : this.goboRotation,
  );

  Map<String, dynamic> toJson() => {'gobo': ?gobo, 'strobe': ?strobe, 'zoom': ?zoom, 'goboRotation': ?goboRotation};

  factory LiveBeamFx.fromJson(Map<String, dynamic> json) => LiveBeamFx(
    gobo: (json['gobo'] as num?)?.toInt(),
    strobe: (json['strobe'] as num?)?.toDouble(),
    zoom: (json['zoom'] as num?)?.toDouble(),
    goboRotation: (json['goboRotation'] as num?)?.toDouble(),
  );
}

/// One cell of the grid: a saved effect configuration for its lane's kind.
/// Only the field matching the lane's kind is used.
class LiveClip {
  final String name;
  final MovementFx? moves;
  final LiveColorFx? colors;
  final LiveLevelFx? level;
  final LiveBeamFx? beam;
  final LiveShowRef? show;

  const LiveClip({required this.name, this.moves, this.colors, this.level, this.beam, this.show});

  LiveClip copyWith({
    String? name,
    MovementFx? moves,
    LiveColorFx? colors,
    LiveLevelFx? level,
    LiveBeamFx? beam,
    LiveShowRef? show,
  }) => LiveClip(
    name: name ?? this.name,
    moves: moves ?? this.moves,
    colors: colors ?? this.colors,
    level: level ?? this.level,
    beam: beam ?? this.beam,
    show: show ?? this.show,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    if (moves != null) 'moves': moves!.toJson(),
    if (colors != null) 'colors': colors!.toJson(),
    if (level != null) 'level': level!.toJson(),
    if (beam != null) 'beam': beam!.toJson(),
    if (show != null) 'show': show!.toJson(),
  };

  factory LiveClip.fromJson(Map<String, dynamic> json) => LiveClip(
    name: json['name'] as String? ?? '',
    moves: MovementFx.fromJson(json['moves']),
    colors: json['colors'] is Map ? LiveColorFx.fromJson((json['colors'] as Map).cast<String, dynamic>()) : null,
    level: json['level'] is Map ? LiveLevelFx.fromJson((json['level'] as Map).cast<String, dynamic>()) : null,
    beam: json['beam'] is Map ? LiveBeamFx.fromJson((json['beam'] as Map).cast<String, dynamic>()) : null,
    show: LiveShowRef.fromJson(json['show']),
  );
}

/// The Live screen's grid: lanes across, rows down, a clip in some cells.
/// A row is also a scene: launching it selects that row's clip on every
/// lane that has one. Saved with the project — the lanes point at fixture
/// groups, which only mean something within one rig.
class LiveGrid {
  final List<LiveLane> lanes;
  final List<String> rows;

  /// `'<laneId>|<row>'` → clip.
  final Map<String, LiveClip> cells;

  const LiveGrid({this.lanes = const [], this.rows = const [], this.cells = const {}});

  static String keyOf(String laneId, int row) => '$laneId|$row';

  bool get isEmpty => lanes.isEmpty;

  LiveClip? clipAt(String laneId, int row) => cells[keyOf(laneId, row)];

  LiveLane? lane(String id) {
    for (final lane in lanes) {
      if (lane.id == id) return lane;
    }
    return null;
  }

  LiveGrid copyWith({List<LiveLane>? lanes, List<String>? rows, Map<String, LiveClip>? cells}) =>
      LiveGrid(lanes: lanes ?? this.lanes, rows: rows ?? this.rows, cells: cells ?? this.cells);

  LiveGrid withClip(String laneId, int row, LiveClip? clip) {
    final next = {...cells};
    if (clip == null) {
      next.remove(keyOf(laneId, row));
    } else {
      next[keyOf(laneId, row)] = clip;
    }
    return copyWith(cells: next);
  }

  LiveGrid withLane(LiveLane lane) => copyWith(lanes: [for (final l in lanes) l.id == lane.id ? lane : l]);

  /// Adds [lane] at the end, or at [index].
  LiveGrid addLane(LiveLane lane, {int? index}) {
    final next = [...lanes];
    next.insert((index ?? next.length).clamp(0, next.length), lane);
    return copyWith(lanes: next);
  }

  /// Drops lane [id] and its clips.
  LiveGrid removeLane(String id) => LiveGrid(
    lanes: [
      for (final l in lanes)
        if (l.id != id) l,
    ],
    rows: rows,
    cells: {
      for (final e in cells.entries)
        if (!e.key.startsWith('$id|')) e.key: e.value,
    },
  );

  /// A lane id not used yet, from [base].
  String freeLaneId(String base) {
    if (lane(base) == null) return base;
    var i = 2;
    while (lane('$base-$i') != null) {
      i++;
    }
    return '$base-$i';
  }

  Map<String, dynamic> toJson() => {
    'lanes': [for (final l in lanes) l.toJson()],
    'rows': rows,
    'cells': {for (final e in cells.entries) e.key: e.value.toJson()},
  };

  factory LiveGrid.fromJson(Map<String, dynamic> json) => LiveGrid(
    lanes: [
      for (final l in json['lanes'] as List? ?? const [])
        if (l is Map) LiveLane.fromJson(l.cast<String, dynamic>()),
    ],
    rows: [for (final r in json['rows'] as List? ?? const []) r.toString()],
    cells: {
      for (final e in (json['cells'] as Map? ?? const {}).entries)
        if (e.value is Map) e.key.toString(): LiveClip.fromJson((e.value as Map).cast<String, dynamic>()),
    },
  );

  /// The grid a new project starts with: one lane per job and five rows of
  /// ready-made clips, so the screen plays something before anyone edits it.
  static LiveGrid starter() {
    const lanes = [
      // Empty until the project's own Banks / Chases / Scenes go on it.
      LiveLane(id: 'show', name: 'Show', kind: LiveLaneKind.show),
      LiveLane(id: 'moves', name: 'Moves', kind: LiveLaneKind.moves, target: LiveTargetKind.heads),
      LiveLane(id: 'colors-heads', name: 'Colors', kind: LiveLaneKind.colors, target: LiveTargetKind.heads),
      LiveLane(id: 'colors-pars', name: 'Colors', kind: LiveLaneKind.colors, target: LiveTargetKind.pars),
      LiveLane(id: 'level', name: 'Level', kind: LiveLaneKind.level, target: LiveTargetKind.all),
      LiveLane(id: 'beam', name: 'Beam', kind: LiveLaneKind.beam, target: LiveTargetKind.heads),
    ];
    const warm = [0xFF6A00, 0xFFB000];
    const cells = <String, LiveClip>{
      // Intro
      'moves|0': LiveClip(
        name: 'Circle',
        moves: MovementFx(
          shape: MovementShape.circle,
          sizePanDeg: 30,
          sizeTiltDeg: 20,
          beatLocked: true,
          beats: 8,
          phaseSpread: 0.25,
        ),
      ),
      'colors-heads|0': LiveClip(
        name: 'Warm',
        colors: LiveColorFx(pattern: LiveColorPattern.step, colors: warm, beats: 8, fade: 1),
      ),
      'colors-pars|0': LiveClip(
        name: 'Warm wash',
        colors: LiveColorFx(pattern: LiveColorPattern.chase, colors: warm, beats: 4, fade: 1),
      ),
      'level|0': LiveClip(
        name: 'Breathe',
        level: LiveLevelFx(pattern: LiveLevelPattern.breathe, low: 0.35, high: 1, beats: 8),
      ),
      'beam|0': LiveClip(name: 'Open', beam: LiveBeamFx(gobo: 0, strobe: 0)),
      // Build
      'moves|1': LiveClip(
        name: 'Eight',
        moves: MovementFx(
          shape: MovementShape.swim,
          sizePanDeg: 45,
          sizeTiltDeg: 25,
          beatLocked: true,
          beats: 4,
          phaseSpread: 0.5,
        ),
      ),
      'colors-heads|1': LiveClip(
        name: 'Rainbow',
        colors: LiveColorFx(pattern: LiveColorPattern.rainbow, beats: 16),
      ),
      'colors-pars|1': LiveClip(
        name: 'Rainbow',
        colors: LiveColorFx(pattern: LiveColorPattern.rainbow, beats: 8),
      ),
      'level|1': LiveClip(
        name: 'Ramp up',
        level: LiveLevelFx(pattern: LiveLevelPattern.ramp, low: 0.2, high: 1, beats: 4),
      ),
      // Drop
      'moves|2': LiveClip(
        name: 'Fan sweep',
        moves: MovementFx(
          shape: MovementShape.lightRider,
          sizePanDeg: 70,
          sizeTiltDeg: 0,
          beatLocked: true,
          beats: 2,
          mirror: true,
        ),
      ),
      'colors-heads|2': LiveClip(
        name: 'Red/white',
        colors: LiveColorFx(pattern: LiveColorPattern.alternate, colors: [0xFF0000, 0xFFFFFF], beats: 1),
      ),
      'colors-pars|2': LiveClip(
        name: 'Red/white',
        colors: LiveColorFx(pattern: LiveColorPattern.alternate, colors: [0xFF0000, 0xFFFFFF], beats: 1),
      ),
      'level|2': LiveClip(
        name: 'Pulse',
        level: LiveLevelFx(pattern: LiveLevelPattern.pulse, low: 0.1, high: 1, beats: 1),
      ),
      'beam|2': LiveClip(name: 'Strobe', beam: LiveBeamFx(strobe: 0.6)),
      // Break
      'moves|3': LiveClip(
        name: 'Wander',
        moves: MovementFx(shape: MovementShape.random, periodSec: 16, phaseSpread: 1, sizePanDeg: 40, sizeTiltDeg: 25),
      ),
      'colors-heads|3': LiveClip(
        name: 'Blue',
        colors: LiveColorFx(colors: [0x0040FF]),
      ),
      'colors-pars|3': LiveClip(
        name: 'Blue/purple',
        colors: LiveColorFx(pattern: LiveColorPattern.chase, colors: [0x0040FF, 0x8C00FF], beats: 4, fade: 1),
      ),
      'level|3': LiveClip(name: 'Dim 40%', level: LiveLevelFx(high: 0.4)),
      'beam|3': LiveClip(name: 'Open', beam: LiveBeamFx(gobo: 0, strobe: 0)),
      // Outro
      'moves|4': LiveClip(
        name: 'Hold',
        moves: MovementFx(shape: MovementShape.hold, sizePanDeg: 0, sizeTiltDeg: 0),
      ),
      'colors-heads|4': LiveClip(
        name: 'Amber',
        colors: LiveColorFx(colors: [0xFFA000]),
      ),
      'colors-pars|4': LiveClip(
        name: 'Amber',
        colors: LiveColorFx(colors: [0xFFA000]),
      ),
      'level|4': LiveClip(
        name: 'Chase',
        level: LiveLevelFx(pattern: LiveLevelPattern.chase, low: 0.1, high: 1, beats: 1, spread: 1),
      ),
    };
    return const LiveGrid(lanes: lanes, rows: ['Intro', 'Build', 'Drop', 'Break', 'Outro'], cells: cells);
  }
}
