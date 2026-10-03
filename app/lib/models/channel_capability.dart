/// What a slice of a channel's 0-255 range does.
enum CapabilityKind {
  /// A discrete choice — one gobo, one colour-wheel position, "prism in".
  /// Any value inside the span does the same thing, so picking it jumps to
  /// the middle where it's safely clear of the neighbours.
  slot,

  /// A continuous span — "strobe 1 Hz to 20 Hz", "fade speed slow to fast".
  /// Where you are *within* the span matters, so picking it lands at the
  /// bottom and you fine-tune from there.
  range,

  /// The inactive end of a channel: shutter closed, no gobo, no macro.
  off;

  String get label => switch (this) {
    CapabilityKind.slot => 'Slot',
    CapabilityKind.range => 'Range',
    CapabilityKind.off => 'Off',
  };
}

/// One labelled DMX value span within a channel.
///
/// Real fixtures rarely use a channel as a plain 0-255 dial. A strobe
/// channel is typically "0-3 closed / 4-7 open / 8-215 strobe slow to fast /
/// 216-255 random", and an RGB par's autofade channel is a stack of
/// programs. Without this the app can only offer a bare fader and you find
/// the value you want by trial and error; with it, every screen can name
/// what the current value actually does and offer the options by name.
class ChannelCapability {
  final int min;
  final int max;
  final String label;
  final CapabilityKind kind;

  /// What a colour-wheel slot looks like, as `#RRGGBB` — or two of them
  /// joined by `/` for a split ("half") colour. Optional: without it the
  /// Scene editor guesses from the label ("Red", "Light blue") and falls
  /// back to a numbered grey swatch.
  final String? colorHex;

  /// Which picture to draw for a gobo slot (one of the names in
  /// `goboGlyphNames`). Optional, guessed from the label the same way.
  final String? glyph;

  const ChannelCapability({
    required this.min,
    required this.max,
    required this.label,
    this.kind = CapabilityKind.slot,
    this.colorHex,
    this.glyph,
  });

  bool contains(int value) => value >= min && value <= max;

  /// The value to send when this capability is chosen by name.
  int get pickValue => kind == CapabilityKind.range ? min : (min + max) ~/ 2;

  /// `12` for a single value, `8-215` for a span — shown next to the label
  /// wherever there's room for it.
  String get rangeLabel => min == max ? '$min' : '$min-$max';

  ChannelCapability copyWith({int? min, int? max, String? label, CapabilityKind? kind}) {
    return ChannelCapability(
      min: min ?? this.min,
      max: max ?? this.max,
      label: label ?? this.label,
      kind: kind ?? this.kind,
      colorHex: colorHex,
      glyph: glyph,
    );
  }

  /// [copyWith] can't clear a field back to null, and these two are the ones
  /// the editor sets to "none".
  ChannelCapability withLook({String? colorHex, String? glyph}) {
    return ChannelCapability(min: min, max: max, label: label, kind: kind, colorHex: colorHex, glyph: glyph);
  }

  Map<String, dynamic> toJson() => {
    'min': min,
    'max': max,
    'label': label,
    'kind': kind.name,
    if (colorHex != null) 'color': colorHex,
    if (glyph != null) 'glyph': glyph,
  };

  factory ChannelCapability.fromJson(Map<String, dynamic> json) {
    final min = (json['min'] as num?)?.toInt() ?? 0;
    final max = (json['max'] as num?)?.toInt() ?? min;
    return ChannelCapability(
      min: min.clamp(0, 255),
      max: max.clamp(min.clamp(0, 255), 255),
      label: json['label'] as String? ?? '',
      kind: CapabilityKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => CapabilityKind.slot,
      ),
      colorHex: json['color'] as String?,
      glyph: json['glyph'] as String?,
    );
  }
}

/// Sorts by [ChannelCapability.min] and drops anything malformed, so a list
/// coming from a file or an importer can be trusted by the UI.
List<ChannelCapability> normalizeCapabilities(Iterable<ChannelCapability> raw) {
  final cleaned = [
    for (final capability in raw)
      if (capability.label.trim().isNotEmpty && capability.max >= capability.min)
        capability.copyWith(label: capability.label.trim()),
  ];
  cleaned.sort((a, b) => a.min.compareTo(b.min));
  return cleaned;
}
