import 'fixture_channel.dart';

enum FixtureCategory { movingHead, rgb, generic }

/// A reusable fixture "personality": name + its channel layout. Either one
/// of the built-in templates, or a user-defined custom fixture.
class FixtureProfile {
  final String id;
  final String name;
  final FixtureCategory category;
  final List<FixtureChannel> channels;
  final bool isBuiltIn;

  const FixtureProfile({
    required this.id,
    required this.name,
    required this.category,
    required this.channels,
    this.isBuiltIn = false,
  });

  int get channelCount => channels.length;

  FixtureProfile copyWith({String? name, FixtureCategory? category, List<FixtureChannel>? channels}) {
    return FixtureProfile(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      channels: channels ?? this.channels,
      isBuiltIn: isBuiltIn,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category.name,
    'channels': channels.map((c) => c.toJson()).toList(),
  };

  factory FixtureProfile.fromJson(Map<String, dynamic> json) {
    return FixtureProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      category: FixtureCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => FixtureCategory.generic,
      ),
      channels: (json['channels'] as List)
          .map((c) => FixtureChannel.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}
