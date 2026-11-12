/// What kind of MIDI message a mapping listens for.
enum MidiTriggerKind {
  /// Note On (a pad or a button on most controllers).
  note,

  /// Control Change (a fader, a knob, or a button sending CC 127/0).
  cc,

  /// Program Change (foot switches and simple preset buttons).
  program;

  static MidiTriggerKind fromName(String? name) =>
      MidiTriggerKind.values.firstWhere((k) => k.name == name, orElse: () => MidiTriggerKind.note);
}

/// The control on the hardware a mapping is bound to: a message type, a
/// MIDI channel (0–15) and a note / CC / program number (0–127).
class MidiTrigger {
  final MidiTriggerKind kind;
  final int channel;
  final int number;

  const MidiTrigger({required this.kind, required this.channel, required this.number});

  /// Short, language-neutral label: "Note C3 · ch 1", "CC 7 · ch 1", "PC 4 · ch 1".
  String get label {
    final ch = 'ch ${channel + 1}';
    return switch (kind) {
      MidiTriggerKind.note => 'Note ${noteName(number)} · $ch',
      MidiTriggerKind.cc => 'CC $number · $ch',
      MidiTriggerKind.program => 'PC ${number + 1} · $ch',
    };
  }

  /// Note number to name, with 60 = C3 (the Yamaha/Ableton convention most
  /// pad controllers print in their editors).
  static String noteName(int number) {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    return '${names[number % 12]}${number ~/ 12 - 2}';
  }

  @override
  bool operator ==(Object other) =>
      other is MidiTrigger && other.kind == kind && other.channel == channel && other.number == number;

  @override
  int get hashCode => Object.hash(kind, channel, number);

  Map<String, dynamic> toJson() => {'kind': kind.name, 'channel': channel, 'number': number};

  factory MidiTrigger.fromJson(Map<String, dynamic> json) => MidiTrigger(
    kind: MidiTriggerKind.fromName(json['kind'] as String?),
    channel: ((json['channel'] as num?)?.toInt() ?? 0).clamp(0, 15),
    number: ((json['number'] as num?)?.toInt() ?? 0).clamp(0, 127),
  );
}

/// What a mapped control does in the app. Every one of these goes through
/// the same shared action (see `core/remote/trigger_actions.dart`) a
/// Dashboard tile or the remote-control endpoint uses, so a pad on a
/// controller and a tap on the screen behave identically.
enum MidiActionKind {
  /// Start or stop a bank, chase or Smart Program ([MidiMapping.targetId]).
  playTarget,

  /// Start whatever played last (the dock's Start).
  resume,

  /// Stop playback, leaving the rig as it is.
  stop,

  /// Stop everything and take every channel to zero.
  blackout,

  beatSync,
  predict,
  autoFade,
  dropout,

  /// Tap tempo: the step speed follows the taps.
  tapTempo,

  /// Lay a colour over the scenes ([MidiMapping.param] = colour id, or
  /// `off` for the scenes' own colours).
  color,

  /// Grand master, 0–100%.
  grandMaster,

  /// Step speed, 30–240 BPM.
  stepSpeed,

  /// Cross-fade time.
  fadeTime,

  movementSize,
  movementSpeed,
  movementShift,
  movementSmooth,
  movementReset;

  /// Follows the position of a fader/knob instead of firing once on a press.
  bool get isContinuous => switch (this) {
    MidiActionKind.grandMaster ||
    MidiActionKind.stepSpeed ||
    MidiActionKind.fadeTime ||
    MidiActionKind.movementSize ||
    MidiActionKind.movementSpeed ||
    MidiActionKind.movementShift ||
    MidiActionKind.movementSmooth => true,
    _ => false,
  };

  static MidiActionKind? fromName(String? name) {
    for (final kind in MidiActionKind.values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

/// What a [MidiActionKind.playTarget] mapping starts.
enum MidiTargetKind {
  bank,
  chase,
  smart;

  static MidiTargetKind fromName(String? name) =>
      MidiTargetKind.values.firstWhere((k) => k.name == name, orElse: () => MidiTargetKind.bank);
}

/// One control on a MIDI controller bound to one thing in the app.
///
/// Mappings belong to the project (like fixture groups), not to the tablet:
/// a pad that starts a bank only means something in the project that has
/// that bank, and a show file carries its controller layout with it.
class MidiMapping {
  final String id;
  final MidiTrigger trigger;
  final MidiActionKind action;

  /// [MidiActionKind.playTarget] only: which bank / chase / Smart Program.
  final MidiTargetKind? targetKind;
  final String? targetId;

  /// Extra parameter for actions that need one — the colour id for
  /// [MidiActionKind.color].
  final String? param;

  const MidiMapping({
    required this.id,
    required this.trigger,
    required this.action,
    this.targetKind,
    this.targetId,
    this.param,
  });

  MidiMapping copyWith({
    MidiTrigger? trigger,
    MidiActionKind? action,
    MidiTargetKind? targetKind,
    String? targetId,
    String? param,
  }) => MidiMapping(
    id: id,
    trigger: trigger ?? this.trigger,
    action: action ?? this.action,
    targetKind: targetKind ?? this.targetKind,
    targetId: targetId ?? this.targetId,
    param: param ?? this.param,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'trigger': trigger.toJson(),
    'action': action.name,
    if (targetKind != null) 'targetKind': targetKind!.name,
    if (targetId != null) 'targetId': targetId,
    if (param != null) 'param': param,
  };

  /// Null for a mapping whose action this version doesn't know (a file saved
  /// by a newer app) — dropped rather than guessed at.
  static MidiMapping? fromJson(Map<String, dynamic> json) {
    final action = MidiActionKind.fromName(json['action'] as String?);
    final trigger = json['trigger'];
    if (action == null || trigger is! Map) return null;
    return MidiMapping(
      id: json['id'] as String? ?? '',
      trigger: MidiTrigger.fromJson(trigger.cast<String, dynamic>()),
      action: action,
      targetKind: json['targetKind'] == null ? null : MidiTargetKind.fromName(json['targetKind'] as String?),
      targetId: json['targetId'] as String?,
      param: json['param'] as String?,
    );
  }
}
