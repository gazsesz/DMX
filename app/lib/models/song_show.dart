import 'smart_program.dart';

/// How a [SongShow] came to be — kept so the editor can offer "regenerate" on
/// an automatic one and so a hand-built one is never overwritten by it.
enum SongShowOrigin { manual, recorded, auto }

/// What a section of the song is, as far as the lights care.
enum SongSectionKind { intro, build, drop, breakdown, outro, custom }

enum SongCueAction {
  /// Start [SongCue.target] on the cue's layer.
  start,

  /// Stop whatever the cue's layer is playing.
  stop,
}

/// A reference to the song's audio file. The audio itself never lives in the
/// project — only enough to recognise it again after a move or an import.
class SongAudioRef {
  final String fileName;
  final int durationMs;

  /// Content hash, filled in once the file has been read; null until then.
  final String? sha1;

  /// Where the file is on *this* device. Local only: an export drops it, and
  /// an import has to relink by name and hash.
  final String? path;

  const SongAudioRef({required this.fileName, required this.durationMs, this.sha1, this.path});

  /// Whether a file of [durationMs] could be the song this refers to: the
  /// length has to agree to within a second and a half (names get changed,
  /// lengths don't). An unknown length matches anything.
  bool couldBeSameSong(int durationMs) => this.durationMs <= 0 || (this.durationMs - durationMs).abs() <= 1500;

  Map<String, dynamic> toJson({bool withPath = true}) => {
    'fileName': fileName,
    'durationMs': durationMs,
    if (sha1 != null) 'sha1': sha1,
    if (withPath && path != null) 'path': path,
  };

  factory SongAudioRef.fromJson(Map<String, dynamic> json) => SongAudioRef(
    fileName: json['fileName'] as String? ?? '',
    durationMs: json['durationMs'] as int? ?? 0,
    sha1: json['sha1'] as String?,
    path: json['path'] as String?,
  );
}

/// A stretch of the song. Cues inside a disabled section are skipped.
class SongSection {
  final double startBeat;
  final double lengthBeats;
  final SongSectionKind kind;
  final String label;
  final bool enabled;

  const SongSection({
    required this.startBeat,
    required this.lengthBeats,
    this.kind = SongSectionKind.custom,
    this.label = '',
    this.enabled = true,
  });

  double get endBeat => startBeat + lengthBeats;

  bool contains(double beat) => beat >= startBeat && beat < endBeat;

  Map<String, dynamic> toJson() => {
    'startBeat': startBeat,
    'lengthBeats': lengthBeats,
    'kind': kind.name,
    if (label.isNotEmpty) 'label': label,
    if (!enabled) 'enabled': false,
  };

  factory SongSection.fromJson(Map<String, dynamic> json) => SongSection(
    startBeat: (json['startBeat'] as num? ?? 0).toDouble(),
    lengthBeats: (json['lengthBeats'] as num? ?? 0).toDouble(),
    kind: SongSectionKind.values.firstWhere((k) => k.name == json['kind'], orElse: () => SongSectionKind.custom),
    label: json['label'] as String? ?? '',
    enabled: json['enabled'] as bool? ?? true,
  );
}

/// One point on the timeline: at [atBeat], [action] happens on [layerId].
class SongCue {
  final String id;
  final double atBeat;
  final String layerId;
  final SongCueAction action;

  /// What a [SongCueAction.start] plays; the same bank-or-chase reference a
  /// Smart Program zone uses. Null for a stop.
  final ProgramTarget? target;

  const SongCue({
    required this.id,
    required this.atBeat,
    required this.layerId,
    this.action = SongCueAction.start,
    this.target,
  });

  SongCue copyWith({double? atBeat, String? layerId, SongCueAction? action, ProgramTarget? target}) => SongCue(
    id: id,
    atBeat: atBeat ?? this.atBeat,
    layerId: layerId ?? this.layerId,
    action: action ?? this.action,
    target: target ?? this.target,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'atBeat': atBeat,
    'layerId': layerId,
    'action': action.name,
    if (target?.chaseId != null) 'chaseId': target!.chaseId,
    if (target?.bankId != null) 'bankId': target!.bankId,
    if (target?.chaseLane != null) 'chaseLane': target!.chaseLane,
  };

  factory SongCue.fromJson(Map<String, dynamic> json) => SongCue(
    id: json['id'] as String,
    atBeat: (json['atBeat'] as num? ?? 0).toDouble(),
    layerId: json['layerId'] as String,
    action: SongCueAction.values.firstWhere((a) => a.name == json['action'], orElse: () => SongCueAction.start),
    target: ProgramTarget.from(
      chaseId: json['chaseId'] as String?,
      bankId: json['bankId'] as String?,
      chaseLane: json['chaseLane'] as String?,
    ),
  );
}

/// A timed program for one song: a beat grid, sections and cues. Time is kept
/// in beats, so nudging the tempo or the grid offset moves every cue with the
/// music instead of leaving it at a fixed second.
class SongShow {
  final String id;
  final String name;
  final SongShowOrigin origin;
  final SongAudioRef? audio;
  final double bpm;

  /// Where beat 0 falls in the audio, in milliseconds.
  final int beatOffsetMs;
  final List<SongSection> sections;
  final List<SongCue> cues;

  /// Fixture groups this show is limited to; empty means every fixture.
  final List<String> groupIds;

  const SongShow({
    required this.id,
    required this.name,
    this.origin = SongShowOrigin.manual,
    this.audio,
    this.bpm = 120,
    this.beatOffsetMs = 0,
    this.sections = const [],
    this.cues = const [],
    this.groupIds = const [],
  });

  double get beatMs => 60000 / bpm;

  double msOfBeat(double beat) => beatOffsetMs + beat * beatMs;

  double beatAtMs(double ms) => (ms - beatOffsetMs) / beatMs;

  /// The section [beat] falls in, if any.
  SongSection? sectionAt(double beat) {
    for (final s in sections) {
      if (s.contains(beat)) return s;
    }
    return null;
  }

  /// Cues in timeline order, minus those inside a disabled section.
  List<SongCue> get activeCues => [
    for (final c in sortedCues)
      if (sectionAt(c.atBeat)?.enabled ?? true) c,
  ];

  List<SongCue> get sortedCues => [...cues]..sort((a, b) => a.atBeat.compareTo(b.atBeat));

  bool usesChase(String chaseId) => cues.any((c) => c.target?.chaseId == chaseId);
  bool usesBank(String bankId) => cues.any((c) => c.target?.bankId == bankId);

  SongShow copyWith({
    String? name,
    SongShowOrigin? origin,
    SongAudioRef? audio,
    double? bpm,
    int? beatOffsetMs,
    List<SongSection>? sections,
    List<SongCue>? cues,
    List<String>? groupIds,
  }) => SongShow(
    id: id,
    name: name ?? this.name,
    origin: origin ?? this.origin,
    audio: audio ?? this.audio,
    bpm: bpm ?? this.bpm,
    beatOffsetMs: beatOffsetMs ?? this.beatOffsetMs,
    sections: sections ?? this.sections,
    cues: cues ?? this.cues,
    groupIds: groupIds ?? this.groupIds,
  );

  SongShow duplicateAs(String newId, String newName) => SongShow(
    id: newId,
    name: newName,
    origin: origin,
    audio: audio,
    bpm: bpm,
    beatOffsetMs: beatOffsetMs,
    sections: sections,
    cues: cues,
    groupIds: groupIds,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'origin': origin.name,
    if (audio != null) 'audio': audio!.toJson(),
    'bpm': bpm,
    'beatOffsetMs': beatOffsetMs,
    'sections': sections.map((s) => s.toJson()).toList(),
    'cues': cues.map((c) => c.toJson()).toList(),
    if (groupIds.isNotEmpty) 'groupIds': groupIds,
  };

  factory SongShow.fromJson(Map<String, dynamic> json) => SongShow(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'Song',
    origin: SongShowOrigin.values.firstWhere((o) => o.name == json['origin'], orElse: () => SongShowOrigin.manual),
    audio: json['audio'] is Map ? SongAudioRef.fromJson(Map<String, dynamic>.from(json['audio'] as Map)) : null,
    bpm: (json['bpm'] as num?)?.toDouble() ?? 120,
    beatOffsetMs: json['beatOffsetMs'] as int? ?? 0,
    sections: (json['sections'] as List? ?? [])
        .map((s) => SongSection.fromJson(Map<String, dynamic>.from(s as Map)))
        .toList(),
    cues: (json['cues'] as List? ?? []).map((c) => SongCue.fromJson(Map<String, dynamic>.from(c as Map))).toList(),
    groupIds: (json['groupIds'] as List? ?? []).cast<String>(),
  );
}
