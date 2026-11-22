import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show setEquals;

/// Which lamps a dropout darkens each time it comes.
enum DropoutPattern {
  /// Every lamp in scope at once (the original behaviour).
  together,

  /// The lamps split into groups that take turns, one group per dropout.
  alternate,

  /// A fresh random pick of the lamps on every dropout.
  random,
}

/// How [DropoutPattern.alternate] splits the lamps, in the project's lamp
/// order (stage left to right unless set otherwise in the generator).
enum DropoutGrouping {
  /// 1st, 3rd, 5th… then 2nd, 4th, 6th…
  oddEven,

  /// The first half of the line, then the second.
  halves,

  /// One lamp at a time, walking the line.
  oneByOne,

  /// The project's saved fixture groups, one after the other.
  groups,
}

/// A dimmer dropout: the light goes dark for a moment, now and then, while
/// whatever else the layer is doing — a slow pan, a colour fade — carries on.
///
/// Like the momentary effects it is an *output* effect: it changes the frame on
/// its way to the node and never touches the buffers the show writes into, so
/// when the dark ends the layer is simply where it would have been.
class DropoutSettings {
  final bool enabled;

  /// Layers the dropout cuts. Empty means every layer, and also channels no
  /// layer owns (a scene fired by hand).
  final Set<String> targetLayerIds;

  /// Fixtures it cuts. Empty means every fixture on the chosen layers.
  final Set<String> fixtureIds;

  /// How long the dark lasts.
  final int lengthMs;

  /// How long the light takes to fade down to dark before the dark itself
  /// starts. 0 is a hard cut.
  final int fadeOutMs;

  /// How long the light takes to come back up after the dark. 0 is a hard cut.
  final int fadeInMs;

  /// The average time between two dropouts, dark included.
  final int intervalMs;

  /// 0 is a metronome, 1 swings each gap between none and double the average.
  final double jitter;

  /// Dark on the beat instead of on a timer: every [beatEvery]-th beat the
  /// light drops for [lengthMs]. [intervalMs] and [jitter] then do nothing.
  /// With no beat source listening it carries on by the timer, so a lost
  /// detector does not silently switch the effect off.
  final bool onBeat;

  /// Which beats drop the light when [onBeat]: every 1st, 2nd, 4th or 8th.
  final int beatEvery;

  /// All at once, taking turns, or a random pick each time.
  final DropoutPattern pattern;

  /// How the lamps are split when they take turns.
  final DropoutGrouping grouping;

  /// Taking turns over more than two groups: there and back again instead of
  /// starting over from the first.
  final bool pingPong;

  /// [DropoutPattern.random]: the share of lamps cut each time (0.1..1),
  /// always at least one.
  final double randomShare;

  /// [DropoutPattern.random]: avoid the lamps the previous dropout cut, so the
  /// dark moves around instead of hitting the same lamp twice in a row.
  final bool noRepeat;

  const DropoutSettings({
    this.enabled = false,
    this.targetLayerIds = const {},
    this.fixtureIds = const {},
    this.lengthMs = 120,
    this.fadeOutMs = 0,
    this.fadeInMs = 0,
    this.intervalMs = 4000,
    this.jitter = 0.5,
    this.onBeat = false,
    this.beatEvery = 1,
    this.pattern = DropoutPattern.together,
    this.grouping = DropoutGrouping.oddEven,
    this.pingPong = false,
    this.randomShare = 0.3,
    this.noRepeat = true,
  });

  // By value: a Smart Program hands its zone's settings over on every zone
  // play, and the controller must be able to tell "same again" from a change
  // or it would restart the dropout's timer each time.
  @override
  bool operator ==(Object other) =>
      other is DropoutSettings &&
      other.enabled == enabled &&
      other.lengthMs == lengthMs &&
      other.fadeOutMs == fadeOutMs &&
      other.fadeInMs == fadeInMs &&
      other.intervalMs == intervalMs &&
      other.jitter == jitter &&
      other.onBeat == onBeat &&
      other.beatEvery == beatEvery &&
      other.pattern == pattern &&
      other.grouping == grouping &&
      other.pingPong == pingPong &&
      other.randomShare == randomShare &&
      other.noRepeat == noRepeat &&
      setEquals(other.targetLayerIds, targetLayerIds) &&
      setEquals(other.fixtureIds, fixtureIds);

  @override
  int get hashCode => Object.hash(
    enabled,
    lengthMs,
    fadeOutMs,
    fadeInMs,
    intervalMs,
    jitter,
    onBeat,
    beatEvery,
    pattern,
    grouping,
    pingPong,
    randomShare,
    noRepeat,
    Object.hashAllUnordered(targetLayerIds),
    Object.hashAllUnordered(fixtureIds),
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'targetLayerIds': targetLayerIds.toList(),
    'fixtureIds': fixtureIds.toList(),
    'lengthMs': lengthMs,
    'fadeOutMs': fadeOutMs,
    'fadeInMs': fadeInMs,
    'intervalMs': intervalMs,
    'jitter': jitter,
    'onBeat': onBeat,
    'beatEvery': beatEvery,
    'pattern': pattern.name,
    'grouping': grouping.name,
    'pingPong': pingPong,
    'randomShare': randomShare,
    'noRepeat': noRepeat,
  };

  /// Tolerant of a missing or hand-edited entry: anything absent or out of
  /// range falls back to the default rather than failing the whole project.
  factory DropoutSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DropoutSettings();
    const base = DropoutSettings();
    return DropoutSettings(
      enabled: json['enabled'] as bool? ?? false,
      targetLayerIds: {...(json['targetLayerIds'] as List? ?? []).whereType<String>()},
      fixtureIds: {...(json['fixtureIds'] as List? ?? []).whereType<String>()},
      lengthMs: ((json['lengthMs'] as num?)?.round() ?? base.lengthMs).clamp(minLengthMs, maxLengthMs),
      fadeOutMs: ((json['fadeOutMs'] as num?)?.round() ?? base.fadeOutMs).clamp(0, maxFadeOutMs),
      fadeInMs: ((json['fadeInMs'] as num?)?.round() ?? base.fadeInMs).clamp(0, maxFadeInMs),
      intervalMs: ((json['intervalMs'] as num?)?.round() ?? base.intervalMs).clamp(minIntervalMs, maxIntervalMs),
      jitter: ((json['jitter'] as num?)?.toDouble() ?? base.jitter).clamp(0.0, 1.0),
      onBeat: json['onBeat'] as bool? ?? false,
      beatEvery: beatDivisions.contains(json['beatEvery']) ? json['beatEvery'] as int : 1,
      pattern: DropoutPattern.values.asNameMap()[json['pattern']] ?? DropoutPattern.together,
      grouping: DropoutGrouping.values.asNameMap()[json['grouping']] ?? DropoutGrouping.oddEven,
      pingPong: json['pingPong'] as bool? ?? false,
      randomShare: ((json['randomShare'] as num?)?.toDouble() ?? base.randomShare).clamp(minRandomShare, 1.0),
      noRepeat: json['noRepeat'] as bool? ?? true,
    );
  }

  static const beatDivisions = [1, 2, 4, 8];
  static const minLengthMs = 30;
  static const maxLengthMs = 500;
  static const maxFadeOutMs = 1000;
  static const maxFadeInMs = maxFadeOutMs;
  static const minIntervalMs = 500;
  static const maxIntervalMs = 20000;
  static const minRandomShare = 0.1;

  DropoutSettings copyWith({
    bool? enabled,
    Set<String>? targetLayerIds,
    Set<String>? fixtureIds,
    int? lengthMs,
    int? fadeOutMs,
    int? fadeInMs,
    int? intervalMs,
    double? jitter,
    bool? onBeat,
    int? beatEvery,
    DropoutPattern? pattern,
    DropoutGrouping? grouping,
    bool? pingPong,
    double? randomShare,
    bool? noRepeat,
  }) => DropoutSettings(
    enabled: enabled ?? this.enabled,
    targetLayerIds: targetLayerIds ?? this.targetLayerIds,
    fixtureIds: fixtureIds ?? this.fixtureIds,
    lengthMs: lengthMs ?? this.lengthMs,
    fadeOutMs: fadeOutMs ?? this.fadeOutMs,
    fadeInMs: fadeInMs ?? this.fadeInMs,
    intervalMs: intervalMs ?? this.intervalMs,
    jitter: jitter ?? this.jitter,
    onBeat: onBeat ?? this.onBeat,
    beatEvery: beatEvery ?? this.beatEvery,
    pattern: pattern ?? this.pattern,
    grouping: grouping ?? this.grouping,
    pingPong: pingPong ?? this.pingPong,
    randomShare: randomShare ?? this.randomShare,
    noRepeat: noRepeat ?? this.noRepeat,
  );
}

/// The lamps [settings] takes turns over, as lists of fixture ids, in the
/// order the turns come. [ordered] is every lamp in scope in the project's
/// lamp order; [groups] the saved fixture groups' ids, for
/// [DropoutGrouping.groups].
///
/// [DropoutPattern.together] is one unit of everything; [DropoutPattern.random]
/// one unit per lamp, to pick from. Taking turns with fewer than two lamps (or
/// groups) falls back to one unit, which is the same as all at once.
List<List<String>> dropoutUnits(
  DropoutSettings settings,
  List<String> ordered, {
  List<List<String>> groups = const [],
}) {
  if (ordered.isEmpty) return const [];
  switch (settings.pattern) {
    case DropoutPattern.together:
      return [ordered];
    case DropoutPattern.random:
      return [
        for (final id in ordered) [id],
      ];
    case DropoutPattern.alternate:
      final units = switch (settings.grouping) {
        DropoutGrouping.oddEven => [
          [for (var i = 0; i < ordered.length; i += 2) ordered[i]],
          [for (var i = 1; i < ordered.length; i += 2) ordered[i]],
        ],
        DropoutGrouping.halves => [
          ordered.sublist(0, (ordered.length + 1) ~/ 2),
          ordered.sublist((ordered.length + 1) ~/ 2),
        ],
        DropoutGrouping.oneByOne => [
          for (final id in ordered) [id],
        ],
        DropoutGrouping.groups => _groupUnits(ordered, groups),
      };
      final kept = [
        for (final u in units)
          if (u.isNotEmpty) u,
      ];
      return kept.length < 2 ? [ordered] : kept;
  }
}

/// Saved groups cut down to the lamps in scope, in the order they were saved.
/// With no usable group it falls back to odd/even, so the choice still does
/// something on a rig without groups.
List<List<String>> _groupUnits(List<String> ordered, List<List<String>> groups) {
  final inScope = ordered.toSet();
  final units = [
    for (final g in groups)
      [
        for (final id in ordered)
          if (g.contains(id) && inScope.contains(id)) id,
      ],
  ].where((u) => u.isNotEmpty).toList();
  if (units.length >= 2) return units;
  return [
    [for (var i = 0; i < ordered.length; i += 2) ordered[i]],
    [for (var i = 1; i < ordered.length; i += 2) ordered[i]],
  ];
}

/// Walks a dropout's units: which of them the next dropout cuts.
class DropoutStepper {
  final DropoutSettings settings;
  final Random _random;
  int _count;

  /// The unit taken last when taking turns (-1 before the first).
  int _index = -1;
  int _direction = 1;

  /// The units the previous random pick cut.
  Set<int> _last = const {};

  DropoutStepper(this.settings, int count, Random random) : _count = count, _random = random;

  /// The patch changed under a running dropout: keep the place in the walk
  /// where it still makes sense.
  set count(int value) {
    _count = value;
    if (_index >= value) _index = -1;
    _last = {
      for (final i in _last)
        if (i < value) i,
    };
  }

  /// Indexes of the units the next dropout cuts.
  Set<int> next() {
    if (_count <= 0) return const {};
    switch (settings.pattern) {
      case DropoutPattern.together:
        return {for (var i = 0; i < _count; i++) i};
      case DropoutPattern.alternate:
        if (_count == 1) return const {0};
        if (settings.pingPong && _count > 2) {
          var step = _index + _direction;
          if (step >= _count || step < 0) {
            _direction = -_direction;
            step = _index + _direction;
          }
          _index = step;
        } else {
          _index = (_index + 1) % _count;
        }
        return {_index};
      case DropoutPattern.random:
        final want = (_count * settings.randomShare).round().clamp(1, _count);
        final fresh = [
          for (var i = 0; i < _count; i++)
            if (!settings.noRepeat || !_last.contains(i)) i,
        ]..shuffle(_random);
        final picked = fresh.take(want).toSet();
        if (picked.length < want) {
          // Not enough fresh lamps: top up from last time's.
          final rest = [
            for (final i in _last)
              if (!picked.contains(i)) i,
          ]..shuffle(_random);
          picked.addAll(rest.take(want - picked.length));
        }
        _last = picked;
        return picked;
    }
  }
}

/// How long the light stays up before the next dropout.
///
/// The dark is part of [DropoutSettings.intervalMs], so the lit part is what's
/// left once it is taken off — and never shorter than a frame or two, or a
/// jittery setting would chain dropouts into one long blackout.
Duration dropoutGap(DropoutSettings settings, Random random) {
  final lit = settings.intervalMs - settings.lengthMs - settings.fadeOutMs - settings.fadeInMs;
  final swing = (random.nextDouble() * 2 - 1) * settings.jitter.clamp(0.0, 1.0);
  final gap = (lit * (1 + swing)).round();
  return Duration(milliseconds: max(gap, 60));
}

/// [frame] with [dark] taken to zero and each [dim] channel scaled by its
/// gain (0..1, a dropout part-way through its fade-out). Returns [frame]
/// itself when there is nothing to cut, so the normal case allocates nothing.
/// Never writes into [frame].
Uint8List applyDropout(Uint8List frame, Set<int> dark, [Map<int, double>? dim]) {
  if (dark.isEmpty && (dim == null || dim.isEmpty)) return frame;
  final out = Uint8List.fromList(frame);
  dim?.forEach((channel, gain) {
    if (channel >= 0 && channel < out.length) out[channel] = (out[channel] * gain.clamp(0.0, 1.0)).round();
  });
  for (final channel in dark) {
    if (channel >= 0 && channel < out.length) out[channel] = 0;
  }
  return out;
}
