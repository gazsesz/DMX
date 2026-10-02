import 'fixture_mounting.dart';
import 'fixture_profile.dart';

/// One physical fixture patched into the show: a profile placed at a
/// starting DMX channel offset within a given universe.
class PatchedFixture {
  final String id;
  final String label;
  final FixtureProfile profile;
  final String universeId;
  final int startChannel; // 0-based offset into the 512-channel universe

  /// Normalized (0..1) position on the 2D stage layout canvas: x runs stage
  /// left to right as seen from the audience, y from upstage (0) down to
  /// the audience edge (1).
  final double layoutX;
  final double layoutY;

  /// How a moving head is rigged, for aiming it at a spot on the stage plan.
  final FixtureMounting mounting;

  const PatchedFixture({
    required this.id,
    required this.label,
    required this.profile,
    required this.universeId,
    required this.startChannel,
    this.layoutX = 0.5,
    this.layoutY = 0.5,
    this.mounting = const FixtureMounting(),
  });

  PatchedFixture copyWith({
    String? label,
    String? universeId,
    int? startChannel,
    double? layoutX,
    double? layoutY,
    FixtureMounting? mounting,
  }) {
    return PatchedFixture(
      id: id,
      label: label ?? this.label,
      profile: profile,
      universeId: universeId ?? this.universeId,
      startChannel: startChannel ?? this.startChannel,
      layoutX: layoutX ?? this.layoutX,
      layoutY: layoutY ?? this.layoutY,
      mounting: mounting ?? this.mounting,
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
      mounting: mounting,
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
    if (!mounting.isDefault) 'mounting': mounting.toJson(),
  };

  factory PatchedFixture.fromJson(Map<String, dynamic> json, List<FixtureProfile> library) {
    final profile = library.firstWhere(
      (p) => p.id == json['profileId'],
      orElse: () => library.first,
    );
    final rawMounting = json['mounting'] as Map<String, dynamic>?;
    return PatchedFixture(
      id: json['id'] as String,
      label: json['label'] as String,
      profile: profile,
      universeId: json['universeId'] as String,
      startChannel: json['startChannel'] as int,
      layoutX: (json['layoutX'] as num?)?.toDouble() ?? 0.5,
      layoutY: (json['layoutY'] as num?)?.toDouble() ?? 0.5,
      mounting: rawMounting == null ? const FixtureMounting() : FixtureMounting.fromJson(rawMounting),
    );
  }
}
