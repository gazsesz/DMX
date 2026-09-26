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

  const Scene({required this.id, required this.name, required this.fixtureValues});

  Scene copyWith({String? name, Map<String, Map<int, int>>? fixtureValues}) {
    return Scene(
      id: id,
      name: name ?? this.name,
      fixtureValues: fixtureValues ?? this.fixtureValues,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'fixtureValues': fixtureValues.map(
      (fixtureId, channels) => MapEntry(fixtureId, channels.map((offset, value) => MapEntry('$offset', value))),
    ),
  };

  factory Scene.fromJson(Map<String, dynamic> json) {
    final raw = json['fixtureValues'] as Map<String, dynamic>? ?? {};
    return Scene(
      id: json['id'] as String,
      name: json['name'] as String,
      fixtureValues: raw.map((fixtureId, value) => MapEntry(fixtureId, _decodeChannels(value))),
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
