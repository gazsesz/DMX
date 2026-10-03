import 'pan_tilt.dart';

/// A named spot the movers go to — "Audience", "Mirror ball", "DJ booth" —
/// saved once per project and recalled in any scene with one tap, the way
/// a console's position palettes work.
///
/// Holds an exact position per fixture rather than one shared value: a
/// "point at the DJ" look needs every head at a different pan/tilt.
/// Recalling it copies the values into the scene; editing the preset later
/// leaves scenes that already used it alone, so an old show can't change
/// under you.
class PositionPreset {
  final String id;
  final String name;

  /// patchedFixtureId -> where that head sits in this preset.
  final Map<String, PanTilt> perFixture;

  const PositionPreset({required this.id, required this.name, required this.perFixture});

  PositionPreset copyWith({String? name, Map<String, PanTilt>? perFixture}) {
    return PositionPreset(id: id, name: name ?? this.name, perFixture: perFixture ?? this.perFixture);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'perFixture': perFixture.map((fixtureId, position) => MapEntry(fixtureId, position.toJson())),
  };

  factory PositionPreset.fromJson(Map<String, dynamic> json) {
    final raw = json['perFixture'] as Map<String, dynamic>? ?? const {};
    return PositionPreset(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Position',
      perFixture: {
        for (final entry in raw.entries)
          entry.key: ?PanTilt.fromJson(entry.value),
      },
    );
  }
}
