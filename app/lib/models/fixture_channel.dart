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

/// A name for each of [channels] (same order) that stays the same across
/// every fixture of the same model, so one set of values can drive a whole
/// group of fixtures without two channels landing on the same value.
///
/// Mostly that's just the function — `pan`, `dimmer` — which also keeps every
/// value saved before this existed reading back the same way. Two channels
/// can share a function though: every Reset/Lamp/Function channel is
/// [ChannelFunction.generic], and a twin-wheel spot has two `colorWheel`s.
/// Generic channels go by their label instead (`generic:reset`), so a
/// "Reset" on one model still lines up with the "Reset" on another, and any
/// repeat after that is numbered (`colorWheel#1`).
List<String> channelKeysFor(List<FixtureChannel> channels) {
  final seen = <String, int>{};
  return [
    for (final channel in channels)
      () {
        final base = channel.function == ChannelFunction.generic
            ? 'generic:${channel.label.trim().toLowerCase()}'
            : channel.function.name;
        final count = seen[base] ?? 0;
        seen[base] = count + 1;
        return count == 0 ? base : '$base#$count';
      }(),
  ];
}
