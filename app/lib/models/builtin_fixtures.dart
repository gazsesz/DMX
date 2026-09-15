import 'channel_capability.dart';
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
///
/// The first six are the fixture's own primaries and secondaries — one or
/// two emitters at full and nothing else. On a screen a blend like
/// `30,70,220` reads as a nicer blue, but on a par can it lights the red
/// and green emitters too and comes out washed out and pale; the deep
/// saturated colours a rig is bought for are the pure ones. The blends
/// that used to hold those names are still here under their own.
const colorPresets = <String, List<int>>{
  'Red': [255, 0, 0],
  'Green': [0, 255, 0],
  'Blue': [0, 0, 255],
  'Yellow': [255, 255, 0],
  'Cyan': [0, 255, 255],
  'Magenta': [255, 0, 255],
  'Orange': [255, 100, 0],
  'Amber': [255, 160, 20],
  'Lime': [140, 255, 40],
  'Grass': [0, 200, 60],
  'Sky': [20, 140, 230],
  'Royal': [30, 70, 220],
  'Indigo': [90, 60, 220],
  'Purple': [160, 40, 220],
  'Pink': [230, 60, 130],
  'White': [255, 255, 255],
  'Warm White': [255, 200, 150],
  'Black': [0, 0, 0],
};

/// Named gobo patterns shown in the Scene editor's gobo picker.
///
/// This is the fallback for a profile that doesn't declare its own value
/// ranges: eight equal 32-wide slices with generic names. It matches almost
/// no real fixture — which is exactly why [ChannelCapability] exists — but
/// it keeps the picker usable for a hand-made profile nobody has filled the
/// ranges in for yet.
const goboPresets = <String>['Open', 'Dots', 'Breakup', 'Stars', 'Stripes', 'Swirl', 'Triangle', 'Prism'];

/// The choices to offer for a gobo (or any other slotted) channel: the
/// fixture's own capability list where it has one, otherwise [goboPresets]
/// spread evenly across 0-255.
List<ChannelCapability> goboChoicesFor(List<ChannelCapability> capabilities) {
  if (capabilities.isNotEmpty) return capabilities;
  return [
    for (var i = 0; i < goboPresets.length; i++)
      ChannelCapability(min: i * 32, max: i * 32 + 31, label: goboPresets[i]),
  ];
}

/// What a gobo channel at [value] is showing, named.
String goboLabelFor(List<ChannelCapability> capabilities, int value) {
  for (final choice in goboChoicesFor(capabilities)) {
    if (choice.contains(value)) return choice.label;
  }
  return '$value';
}
