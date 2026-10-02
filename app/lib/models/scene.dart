import 'group_position.dart';

/// A saved lighting look: a snapshot of channel values per patched fixture.
class Scene {
  final String id;
  final String name;

  /// patchedFixtureId -> (channel offset within that fixture -> value).
  ///
  /// Sparse on purpose: a channel simply absent from the inner map is left
  /// untouched at playback, exactly like a fixture absent from the outer map
  /// is today. This is what lets two fixtures — or two Layers sharing one
  /// fixture — divide a moving head's attributes between them (e.g. one
  /// scene drives only Color/Beam, another only Position) instead of every
  /// scene always specifying every channel.
  final Map<String, Map<int, int>> fixtureValues;

  /// The editor's own "which fixtures share a look" grouping, as the sets of
  /// fixture ids the user last arranged — one inner list per group, in
  /// order. Saved explicitly rather than re-inferred from matching channel
  /// values on reopen: two groups that happen to land on the same colour (or
  /// a group split off before its colour was changed) would otherwise
  /// silently re-merge, which is exactly what looked like "the grouping
  /// didn't save". Null for scenes saved before this existed, or built
  /// programmatically (e.g. the Beat Flash preset) — the editor falls back
  /// to clustering by value in that case.
  final List<List<String>>? fixtureGroups;

  /// The editor's position settings for each of [fixtureGroups] (same
  /// order): fan, per-head positions, stage aim — see [GroupPosition]. Null
  /// entries (and a null list) are groups with a single plain pan/tilt or
  /// no movers at all. Playback never reads this; [fixtureValues] already
  /// holds every head's resolved position.
  final List<GroupPosition?>? groupPositions;

  const Scene({
    required this.id,
    required this.name,
    required this.fixtureValues,
    this.fixtureGroups,
    this.groupPositions,
  });

  Scene copyWith({
    String? name,
    Map<String, Map<int, int>>? fixtureValues,
    List<List<String>>? fixtureGroups,
    List<GroupPosition?>? groupPositions,
  }) {
    return Scene(
      id: id,
      name: name ?? this.name,
      fixtureValues: fixtureValues ?? this.fixtureValues,
      fixtureGroups: fixtureGroups ?? this.fixtureGroups,
      groupPositions: groupPositions ?? this.groupPositions,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'fixtureValues': fixtureValues.map(
      (fixtureId, channels) => MapEntry(fixtureId, channels.map((offset, value) => MapEntry('$offset', value))),
    ),
    if (fixtureGroups != null) 'fixtureGroups': fixtureGroups,
    if (groupPositions != null && groupPositions!.any((p) => p != null))
      'groupPositions': [for (final p in groupPositions!) p?.toJson()],
  };

  factory Scene.fromJson(Map<String, dynamic> json) {
    final raw = json['fixtureValues'] as Map<String, dynamic>? ?? {};
    final rawGroups = json['fixtureGroups'] as List?;
    final rawPositions = json['groupPositions'] as List?;
    return Scene(
      id: json['id'] as String,
      name: json['name'] as String,
      fixtureValues: raw.map((fixtureId, value) => MapEntry(fixtureId, _decodeChannels(value))),
      fixtureGroups: rawGroups?.map((g) => (g as List).cast<String>()).toList(),
      groupPositions: rawPositions
          ?.map((p) => p is Map<String, dynamic> ? GroupPosition.fromJson(p) : null)
          .toList(),
    );
  }

  /// Reads either shape a project file can carry: the old one (a plain list,
  /// index == channel offset, every channel always present) from before
  /// scenes could leave channels out, or the current sparse `{"offset":
  /// value}` map — so older shows keep loading and playing exactly as they
  /// did.
  static Map<int, int> _decodeChannels(dynamic value) {
    if (value is List) {
      return {for (var i = 0; i < value.length; i++) i: (value[i] as num).toInt()};
    }
    final map = value as Map<String, dynamic>;
    return map.map((offset, v) => MapEntry(int.parse(offset), (v as num).toInt()));
  }
}
