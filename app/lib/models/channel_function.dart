enum ChannelFunction {
  dimmer,
  red,
  green,
  blue,
  white,
  amber,
  uv,
  strobe,
  pan,
  panFine,
  tilt,
  tiltFine,
  gobo,
  goboRotation,
  colorWheel,
  zoom,
  focus,
  prism,
  prismRotation,
  frost,
  panTiltSpeed,
  autofade,
  generic;

  String get label {
    switch (this) {
      case ChannelFunction.dimmer:
        return 'Dimmer';
      case ChannelFunction.red:
        return 'Red';
      case ChannelFunction.green:
        return 'Green';
      case ChannelFunction.blue:
        return 'Blue';
      case ChannelFunction.white:
        return 'White';
      case ChannelFunction.amber:
        return 'Amber';
      case ChannelFunction.uv:
        return 'UV';
      case ChannelFunction.strobe:
        return 'Strobe';
      case ChannelFunction.pan:
        return 'Pan';
      case ChannelFunction.panFine:
        return 'Pan Fine';
      case ChannelFunction.tilt:
        return 'Tilt';
      case ChannelFunction.tiltFine:
        return 'Tilt Fine';
      case ChannelFunction.gobo:
        return 'Gobo Wheel';
      case ChannelFunction.goboRotation:
        return 'Gobo Rotation';
      case ChannelFunction.colorWheel:
        return 'Color Wheel';
      case ChannelFunction.zoom:
        return 'Zoom';
      case ChannelFunction.focus:
        return 'Focus';
      case ChannelFunction.prism:
        return 'Prism';
      case ChannelFunction.prismRotation:
        return 'Prism Rotation';
      case ChannelFunction.frost:
        return 'Frost';
      case ChannelFunction.panTiltSpeed:
        return 'Pan/Tilt Speed';
      case ChannelFunction.autofade:
        return 'Autofade';
      case ChannelFunction.generic:
        return 'Generic';
    }
  }

  bool get isDimmer => this == dimmer;

  bool get isColorMix =>
      this == red || this == green || this == blue || this == white || this == amber || this == uv;
  bool get isPanTilt => this == pan || this == panFine || this == tilt || this == tiltFine;
  bool get isGobo => this == gobo || this == goboRotation;
  bool get isPrism => this == prism || this == prismRotation;

  /// Which broad attribute a channel belongs to, for deciding what a Scene
  /// (or a Layer) controls independently of the others — a moving head's
  /// position can be owned by one program while its colour is owned by
  /// another. [AttributeGroup.other] covers strobe/zoom/focus/autofade/
  /// generic, none of which have their own group yet.
  ///
  /// Pan/tilt speed rides with Position: a scene that leaves the position to
  /// another program has to leave how fast it gets there alone too.
  AttributeGroup get attributeGroup {
    if (isDimmer) return AttributeGroup.dimmer;
    if (isColorMix) return AttributeGroup.color;
    if (isPanTilt || this == panTiltSpeed) return AttributeGroup.position;
    if (isGobo || isPrism || this == colorWheel || this == frost) return AttributeGroup.beam;
    return AttributeGroup.other;
  }
}

/// A channel's function grouped into the handful of attributes a Scene can
/// choose to control (or leave alone) independently of the others.
enum AttributeGroup { dimmer, color, position, beam, other }

extension AttributeGroupLabel on AttributeGroup {
  String get label => switch (this) {
    AttributeGroup.dimmer => 'Dimmer',
    AttributeGroup.color => 'Color',
    AttributeGroup.position => 'Position',
    AttributeGroup.beam => 'Beam',
    AttributeGroup.other => 'Other',
  };
}
