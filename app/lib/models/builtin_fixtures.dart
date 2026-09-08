import 'channel_function.dart';
import 'fixture_channel.dart';
import 'fixture_profile.dart';

/// Fixture templates that ship with the app.
final builtInFixtureProfiles = <FixtureProfile>[
  FixtureProfile(
    id: 'builtin-moving-head-spot',
    name: 'Moving Head Spot',
    category: FixtureCategory.movingHead,
    isBuiltIn: true,
    channels: const [
      FixtureChannel(offset: 0, function: ChannelFunction.pan),
      FixtureChannel(offset: 1, function: ChannelFunction.panFine),
      FixtureChannel(offset: 2, function: ChannelFunction.tilt),
      FixtureChannel(offset: 3, function: ChannelFunction.tiltFine),
      FixtureChannel(offset: 4, function: ChannelFunction.dimmer),
      FixtureChannel(offset: 5, function: ChannelFunction.strobe),
      FixtureChannel(offset: 6, function: ChannelFunction.red),
      FixtureChannel(offset: 7, function: ChannelFunction.green),
      FixtureChannel(offset: 8, function: ChannelFunction.blue),
      FixtureChannel(offset: 9, function: ChannelFunction.white),
      FixtureChannel(offset: 10, function: ChannelFunction.gobo),
      FixtureChannel(offset: 11, function: ChannelFunction.goboRotation),
    ],
  ),
  FixtureProfile(
    id: 'builtin-moving-head-beam',
    name: 'Moving Head Beam',
    category: FixtureCategory.movingHead,
    isBuiltIn: true,
    channels: const [
      FixtureChannel(offset: 0, function: ChannelFunction.pan),
      FixtureChannel(offset: 1, function: ChannelFunction.tilt),
      FixtureChannel(offset: 2, function: ChannelFunction.dimmer),
      FixtureChannel(offset: 3, function: ChannelFunction.strobe),
      FixtureChannel(offset: 4, function: ChannelFunction.colorWheel),
      FixtureChannel(offset: 5, function: ChannelFunction.gobo),
      FixtureChannel(offset: 6, function: ChannelFunction.goboRotation),
      FixtureChannel(offset: 7, function: ChannelFunction.zoom),
      FixtureChannel(offset: 8, function: ChannelFunction.focus),
      FixtureChannel(offset: 9, function: ChannelFunction.generic, customLabel: 'Prism'),
      FixtureChannel(offset: 10, function: ChannelFunction.generic, customLabel: 'Frost'),
      FixtureChannel(offset: 11, function: ChannelFunction.generic, customLabel: 'Reset'),
      FixtureChannel(offset: 12, function: ChannelFunction.generic, customLabel: 'Speed'),
      FixtureChannel(offset: 13, function: ChannelFunction.generic, customLabel: 'Function'),
    ],
  ),
  FixtureProfile(
    id: 'builtin-rgb-par',
    name: 'RGB PAR Can',
    category: FixtureCategory.rgb,
    isBuiltIn: true,
    channels: const [
      FixtureChannel(offset: 0, function: ChannelFunction.dimmer),
      FixtureChannel(offset: 1, function: ChannelFunction.red),
      FixtureChannel(offset: 2, function: ChannelFunction.green),
      FixtureChannel(offset: 3, function: ChannelFunction.blue),
    ],
  ),
  FixtureProfile(
    id: 'builtin-rgbw-par',
    name: 'RGBW PAR',
    category: FixtureCategory.rgb,
    isBuiltIn: true,
    channels: const [
      FixtureChannel(offset: 0, function: ChannelFunction.dimmer),
      FixtureChannel(offset: 1, function: ChannelFunction.red),
      FixtureChannel(offset: 2, function: ChannelFunction.green),
      FixtureChannel(offset: 3, function: ChannelFunction.blue),
      FixtureChannel(offset: 4, function: ChannelFunction.white),
    ],
  ),
];

/// Named colour presets shown in the Scene editor's quick-color palette.
const colorPresets = <String, List<int>>{
  'Red': [255, 0, 0],
  'Orange': [255, 100, 0],
  'Amber': [255, 160, 20],
  'Yellow': [255, 220, 0],
  'Lime': [140, 255, 40],
  'Green': [0, 200, 60],
  'Cyan': [0, 210, 220],
  'Sky': [20, 140, 230],
  'Blue': [30, 70, 220],
  'Indigo': [90, 60, 220],
  'Purple': [160, 40, 220],
  'Magenta': [220, 40, 200],
  'Pink': [230, 60, 130],
  'White': [255, 255, 255],
  'Warm White': [255, 200, 150],
  'Black': [0, 0, 0],
};

/// Named gobo patterns shown in the Scene editor's gobo picker.
const goboPresets = <String>['Open', 'Dots', 'Breakup', 'Stars', 'Stripes', 'Swirl', 'Triangle', 'Prism'];
