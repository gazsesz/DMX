/// A saved lighting look: a snapshot of channel values per patched fixture.
class Scene {
  final String id;
  final String name;

  /// patchedFixtureId -> channel values, one entry per channel in that
  /// fixture's profile (index == channel offset).
  final Map<String, List<int>> fixtureValues;

  const Scene({required this.id, required this.name, required this.fixtureValues});

  Scene copyWith({String? name, Map<String, List<int>>? fixtureValues}) {
    return Scene(
      id: id,
      name: name ?? this.name,
      fixtureValues: fixtureValues ?? this.fixtureValues,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'fixtureValues': fixtureValues,
  };

  factory Scene.fromJson(Map<String, dynamic> json) {
    final raw = json['fixtureValues'] as Map<String, dynamic>? ?? {};
    return Scene(
      id: json['id'] as String,
      name: json['name'] as String,
      fixtureValues: raw.map((key, value) => MapEntry(key, (value as List).cast<int>())),
    );
  }
}
