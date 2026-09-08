import 'channel_function.dart';

/// One channel offset (0-based within the fixture) and what it controls.
class FixtureChannel {
  final int offset;
  final ChannelFunction function;
  final String? customLabel;

  const FixtureChannel({required this.offset, required this.function, this.customLabel});

  String get label => customLabel ?? function.label;

  FixtureChannel copyWith({ChannelFunction? function, String? customLabel}) {
    return FixtureChannel(
      offset: offset,
      function: function ?? this.function,
      customLabel: customLabel ?? this.customLabel,
    );
  }

  Map<String, dynamic> toJson() => {
    'offset': offset,
    'function': function.name,
    if (customLabel != null) 'customLabel': customLabel,
  };

  factory FixtureChannel.fromJson(Map<String, dynamic> json) {
    return FixtureChannel(
      offset: json['offset'] as int,
      function: ChannelFunction.values.firstWhere(
        (f) => f.name == json['function'],
        orElse: () => ChannelFunction.generic,
      ),
      customLabel: json['customLabel'] as String?,
    );
  }
}
