/// A saved lighting look: a snapshot of channel values per patched fixture.
class Scene {
  final String id;
  final String name;

  /// patchedFixtureId -> channel values, one entry per channel in that
  /// fixture's profile (index == channel offset).
  final Map<String, List<int>> fixtureValues;

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

  const Scene({
    required this.id,
    required this.name,
    required this.fixtureValues,
    this.fixtureGroups,
  });

  Scene copyWith({
    String? name,
    Map<String, List<int>>? fixtureValues,
    List<List<String>>? fixtureGroups,
  }) {
    return Scene(
      id: id,
      name: name ?? this.name,
      fixtureValues: fixtureValues ?? this.fixtureValues,
      fixtureGroups: fixtureGroups ?? this.fixtureGroups,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'fixtureValues': fixtureValues,
    if (fixtureGroups != null) 'fixtureGroups': fixtureGroups,
  };

  factory Scene.fromJson(Map<String, dynamic> json) {
    final raw = json['fixtureValues'] as Map<String, dynamic>? ?? {};
    final rawGroups = json['fixtureGroups'] as List?;
    return Scene(
      id: json['id'] as String,
      name: json['name'] as String,
      fixtureValues: raw.map((key, value) => MapEntry(key, (value as List).cast<int>())),
      fixtureGroups: rawGroups?.map((g) => (g as List).cast<String>()).toList(),
    );
  }
}
