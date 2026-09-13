import 'channel_capability.dart';
import 'channel_function.dart';

/// One channel offset (0-based within the fixture) and what it controls.
class FixtureChannel {
  final int offset;
  final ChannelFunction function;
  final String? customLabel;

  /// The labelled value spans of this channel, if they're known — see
  /// [ChannelCapability]. Empty means "plain 0-255 dial", which is how
  /// every fixture behaved before ranges existed, so leaving this out keeps
  /// older projects working unchanged.
  final List<ChannelCapability> capabilities;

  const FixtureChannel({
    required this.offset,
    required this.function,
    this.customLabel,
    this.capabilities = const [],
  });

  String get label => customLabel ?? function.label;

  bool get hasCapabilities => capabilities.isNotEmpty;

  /// The capability covering [value], or null when the channel has none
  /// defined or the value falls in a gap.
  ChannelCapability? capabilityFor(int value) {
    for (final capability in capabilities) {
      if (capability.contains(value)) return capability;
    }
    return null;
  }

  FixtureChannel copyWith({
    ChannelFunction? function,
    String? customLabel,
    List<ChannelCapability>? capabilities,
  }) {
    return FixtureChannel(
      offset: offset,
      function: function ?? this.function,
      customLabel: customLabel ?? this.customLabel,
      capabilities: capabilities ?? this.capabilities,
    );
  }

  Map<String, dynamic> toJson() => {
    'offset': offset,
    'function': function.name,
    if (customLabel != null) 'customLabel': customLabel,
    if (capabilities.isNotEmpty) 'capabilities': [for (final c in capabilities) c.toJson()],
  };

  factory FixtureChannel.fromJson(Map<String, dynamic> json) {
    return FixtureChannel(
      offset: json['offset'] as int,
      function: ChannelFunction.values.firstWhere(
        (f) => f.name == json['function'],
        orElse: () => ChannelFunction.generic,
      ),
      customLabel: json['customLabel'] as String?,
      capabilities: normalizeCapabilities([
        for (final c in (json['capabilities'] as List? ?? const []))
          ChannelCapability.fromJson(c as Map<String, dynamic>),
      ]),
    );
  }
}
