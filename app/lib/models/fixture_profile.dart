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

  /// Where this profile came from, when it was imported rather than typed
  /// in. None of it drives behaviour today — it's carried so that an
  /// imported fixture can be traced back to its source and exported without
  /// inventing the manufacturer and mode names again.
  final String? manufacturer;
  final String? model;
  final String? modeName;
  final String? sourceFormat;

  const FixtureProfile({
    required this.id,
    required this.name,
    required this.category,
    required this.channels,
    this.isBuiltIn = false,
    this.manufacturer,
    this.model,
    this.modeName,
    this.sourceFormat,
  });

  int get channelCount => channels.length;

  /// "Chauvet Intimidator Spot 260 · 12ch" where that's known, otherwise
  /// just the name — for list rows and pickers.
  String get qualifiedName {
    final parts = [
      if (manufacturer != null && manufacturer!.isNotEmpty) manufacturer,
      name,
    ].join(' ');
    return modeName == null || modeName!.isEmpty ? parts : '$parts · $modeName';
  }

  FixtureProfile copyWith({
    String? name,
    FixtureCategory? category,
    List<FixtureChannel>? channels,
    String? manufacturer,
    String? model,
    String? modeName,
    String? sourceFormat,
  }) {
    return FixtureProfile(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      channels: channels ?? this.channels,
      isBuiltIn: isBuiltIn,
      manufacturer: manufacturer ?? this.manufacturer,
      model: model ?? this.model,
      modeName: modeName ?? this.modeName,
      sourceFormat: sourceFormat ?? this.sourceFormat,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category.name,
    'channels': channels.map((c) => c.toJson()).toList(),
    if (manufacturer != null) 'manufacturer': manufacturer,
    if (model != null) 'model': model,
    if (modeName != null) 'modeName': modeName,
    if (sourceFormat != null) 'sourceFormat': sourceFormat,
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
      manufacturer: json['manufacturer'] as String?,
      model: json['model'] as String?,
      modeName: json['modeName'] as String?,
      sourceFormat: json['sourceFormat'] as String?,
    );
  }
}
