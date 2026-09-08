import 'fixture_profile.dart';

/// One physical fixture patched into the show: a profile placed at a
/// starting DMX channel offset within a given universe.
class PatchedFixture {
  final String id;
  final String label;
  final FixtureProfile profile;
  final String universeId;
  final int startChannel; // 0-based offset into the 512-channel universe

  /// Normalized (0..1) position on the 2D stage layout canvas.
  final double layoutX;
  final double layoutY;

  const PatchedFixture({
    required this.id,
    required this.label,
    required this.profile,
    required this.universeId,
    required this.startChannel,
    this.layoutX = 0.5,
    this.layoutY = 0.5,
  });

  PatchedFixture copyWith({
    String? label,
    String? universeId,
    int? startChannel,
    double? layoutX,
    double? layoutY,
  }) {
    return PatchedFixture(
      id: id,
      label: label ?? this.label,
      profile: profile,
      universeId: universeId ?? this.universeId,
      startChannel: startChannel ?? this.startChannel,
      layoutX: layoutX ?? this.layoutX,
      layoutY: layoutY ?? this.layoutY,
    );
  }

  PatchedFixture withProfile(FixtureProfile newProfile) {
    return PatchedFixture(
      id: id,
      label: label,
      profile: newProfile,
      universeId: universeId,
      startChannel: startChannel,
      layoutX: layoutX,
      layoutY: layoutY,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'profileId': profile.id,
    'universeId': universeId,
    'startChannel': startChannel,
    'layoutX': layoutX,
    'layoutY': layoutY,
  };

  factory PatchedFixture.fromJson(Map<String, dynamic> json, List<FixtureProfile> library) {
    final profile = library.firstWhere(
      (p) => p.id == json['profileId'],
      orElse: () => library.first,
    );
    return PatchedFixture(
      id: json['id'] as String,
      label: json['label'] as String,
      profile: profile,
      universeId: json['universeId'] as String,
      startChannel: json['startChannel'] as int,
      layoutX: (json['layoutX'] as num?)?.toDouble() ?? 0.5,
      layoutY: (json['layoutY'] as num?)?.toDouble() ?? 0.5,
    );
  }
}
