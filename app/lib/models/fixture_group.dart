/// A named, reusable set of patched fixtures — e.g. "Front", "Back",
/// "Moving" — saved once and then reused across scenes and chases instead
/// of re-selecting the same fixtures by hand every time.
///
/// Tied to a specific rig (its [fixtureIds] are [PatchedFixture] ids, which
/// only exist within one project), so it travels in the project file
/// alongside patched fixtures rather than in app-wide settings.
class FixtureGroup {
  final String id;
  final String name;
  final String iconKey;
  final List<String> fixtureIds;

  const FixtureGroup({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.fixtureIds,
  });

  FixtureGroup copyWith({String? name, String? iconKey, List<String>? fixtureIds}) {
    return FixtureGroup(
      id: id,
      name: name ?? this.name,
      iconKey: iconKey ?? this.iconKey,
      fixtureIds: fixtureIds ?? this.fixtureIds,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'iconKey': iconKey,
    'fixtureIds': fixtureIds,
  };

  factory FixtureGroup.fromJson(Map<String, dynamic> json) {
    return FixtureGroup(
      id: json['id'] as String,
      name: json['name'] as String,
      iconKey: json['iconKey'] as String? ?? 'all',
      fixtureIds: (json['fixtureIds'] as List? ?? []).map((e) => e as String).toList(),
    );
  }
}
