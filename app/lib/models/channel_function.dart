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
      case ChannelFunction.generic:
        return 'Generic';
    }
  }

  bool get isColorMix => this == red || this == green || this == blue || this == white || this == amber;
  bool get isPanTilt => this == pan || this == panFine || this == tilt || this == tiltFine;
  bool get isGobo => this == gobo || this == goboRotation;
}
