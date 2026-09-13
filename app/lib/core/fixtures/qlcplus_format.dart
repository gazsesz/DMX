import 'package:xml/xml.dart';

import '../../models/channel_capability.dart';
import '../../models/channel_function.dart';
import '../../models/fixture_channel.dart';
import '../../models/fixture_profile.dart';

/// Reading and writing QLC+ fixture definitions (`.qxf`).
///
/// This is the interchange format the app leans on: it's plain XML, it's
/// Apache-2.0 licensed so the definitions can be bundled, and between QLC+
/// itself and the Open Fixture Library's QLC+ export it covers most of what
/// a user would want to bring in or take out.
///
/// The same code runs at build time (tool/build_fixture_library.dart, to
/// bake the bundled library) and at runtime (importing a file the user
/// downloaded), so a fixture behaves identically whichever way it arrived.

/// A capability wider than this is treated as a continuous span you
/// fine-tune (a strobe speed sweep) rather than a fixed choice (one gobo).
/// QLC+ doesn't record the difference, and all it changes is whether
/// picking by name jumps to the bottom of the span or to its middle.
const qlcRangeWidthThreshold = 24;

/// QLC+ channel presets → this app's [ChannelFunction]s.
///
/// About two thirds of QLC+ channels carry one of these; the rest fall
/// through to [functionFromGroupAndName].
const qlcPresetToFunction = <String, ChannelFunction>{
  'IntensityDimmer': ChannelFunction.dimmer,
  'IntensityMasterDimmer': ChannelFunction.dimmer,
  'IntensityRed': ChannelFunction.red,
  'IntensityGreen': ChannelFunction.green,
  'IntensityBlue': ChannelFunction.blue,
  'IntensityWhite': ChannelFunction.white,
  'IntensityAmber': ChannelFunction.amber,
  'IntensityUV': ChannelFunction.uv,
  'PositionPan': ChannelFunction.pan,
  'PositionPanFine': ChannelFunction.panFine,
  'PositionTilt': ChannelFunction.tilt,
  'PositionTiltFine': ChannelFunction.tiltFine,
  'ShutterStrobeSlowFast': ChannelFunction.strobe,
  'ShutterStrobeFastSlow': ChannelFunction.strobe,
  'ColorMacro': ChannelFunction.colorWheel,
  'ColorWheel': ChannelFunction.colorWheel,
  'ColorDoubleMacro': ChannelFunction.colorWheel,
  'GoboMacro': ChannelFunction.gobo,
  'GoboWheel': ChannelFunction.gobo,
  'GoboShakeMacro': ChannelFunction.gobo,
  'GoboIndex': ChannelFunction.goboRotation,
  'BeamZoomSmallBig': ChannelFunction.zoom,
  'BeamZoomBigSmall': ChannelFunction.zoom,
  'BeamFocusNearFar': ChannelFunction.focus,
  'BeamFocusFarNear': ChannelFunction.focus,
  'NoFunction': ChannelFunction.generic,
};

/// The reverse map, for export. Only the functions QLC+ has a preset for;
/// anything else is written as a plain grouped channel.
const _functionToQlcPreset = <ChannelFunction, String>{
  ChannelFunction.dimmer: 'IntensityDimmer',
  ChannelFunction.red: 'IntensityRed',
  ChannelFunction.green: 'IntensityGreen',
  ChannelFunction.blue: 'IntensityBlue',
  ChannelFunction.white: 'IntensityWhite',
  ChannelFunction.amber: 'IntensityAmber',
  ChannelFunction.uv: 'IntensityUV',
  ChannelFunction.pan: 'PositionPan',
  ChannelFunction.panFine: 'PositionPanFine',
  ChannelFunction.tilt: 'PositionTilt',
  ChannelFunction.tiltFine: 'PositionTiltFine',
  ChannelFunction.strobe: 'ShutterStrobeSlowFast',
  ChannelFunction.colorWheel: 'ColorMacro',
  ChannelFunction.gobo: 'GoboMacro',
  ChannelFunction.goboRotation: 'GoboIndex',
  ChannelFunction.zoom: 'BeamZoomSmallBig',
  ChannelFunction.focus: 'BeamFocusNearFar',
};

/// The QLC+ `<Group>` each function belongs to, for export.
String qlcGroupFor(ChannelFunction function) {
  switch (function) {
    case ChannelFunction.dimmer:
      return 'Intensity';
    case ChannelFunction.red:
    case ChannelFunction.green:
    case ChannelFunction.blue:
    case ChannelFunction.white:
    case ChannelFunction.amber:
    case ChannelFunction.uv:
    case ChannelFunction.colorWheel:
      return 'Colour';
    case ChannelFunction.pan:
    case ChannelFunction.panFine:
      return 'Pan';
    case ChannelFunction.tilt:
    case ChannelFunction.tiltFine:
      return 'Tilt';
    case ChannelFunction.strobe:
      return 'Shutter';
    case ChannelFunction.gobo:
    case ChannelFunction.goboRotation:
      return 'Gobo';
    case ChannelFunction.zoom:
    case ChannelFunction.focus:
      return 'Beam';
    case ChannelFunction.autofade:
      return 'Effect';
    case ChannelFunction.generic:
      return 'Maintenance';
  }
}

/// Fallback for the third of QLC+ channels with no preset: the `<Group>`
/// plus the channel's own name.
ChannelFunction functionFromGroupAndName(String group, String name) {
  final n = name.toLowerCase();
  bool has(String needle) => n.contains(needle);

  if (has('fine')) {
    if (has('pan')) return ChannelFunction.panFine;
    if (has('tilt')) return ChannelFunction.tiltFine;
  }
  if (has('pan')) return ChannelFunction.pan;
  if (has('tilt')) return ChannelFunction.tilt;
  if (has('strob') || has('shutter')) return ChannelFunction.strobe;
  if (has('dimmer') || has('intensity') || has('master')) return ChannelFunction.dimmer;
  if (has('gobo') && (has('rot') || has('index'))) return ChannelFunction.goboRotation;
  if (has('gobo')) return ChannelFunction.gobo;
  if (has('colour wheel') || has('color wheel') || has('colour macro') || has('color macro')) {
    return ChannelFunction.colorWheel;
  }
  if (n == 'red' || has(' red')) return ChannelFunction.red;
  if (n == 'green' || has(' green')) return ChannelFunction.green;
  if (n == 'blue' || has(' blue')) return ChannelFunction.blue;
  if (n == 'white' || has(' white')) return ChannelFunction.white;
  if (n == 'amber') return ChannelFunction.amber;
  if (has('uv')) return ChannelFunction.uv;
  if (has('zoom')) return ChannelFunction.zoom;
  if (has('focus')) return ChannelFunction.focus;
  // Auto-programs and sound-active channels are exactly what this app's
  // "autofade" function is for.
  if (has('auto') || has('program') || has('sound') || has('fade')) return ChannelFunction.autofade;

  switch (group) {
    case 'Pan':
      return ChannelFunction.pan;
    case 'Tilt':
      return ChannelFunction.tilt;
    case 'Shutter':
      return ChannelFunction.strobe;
    case 'Intensity':
      return ChannelFunction.dimmer;
    case 'Gobo':
      return ChannelFunction.gobo;
    case 'Effect':
      // QLC+'s Effect group is where built-in programs, chases and
      // sound-active modes live — the app's autofade function exactly.
      return ChannelFunction.autofade;
    default:
      // Maintenance covers reset, lamp on/off and catch-all "Function"
      // channels. Guessing between them would be wrong more often than
      // right, and generic keeps the channel's own name and value ranges,
      // which is what actually makes it usable.
      return ChannelFunction.generic;
  }
}

/// QLC+ `<Type>` → one of this app's three categories, which only drive
/// icons and grouping, so a coarse mapping is enough.
FixtureCategory categoryForQlcType(String type) {
  switch (type) {
    case 'Moving Head':
    case 'Scanner':
      return FixtureCategory.movingHead;
    case 'Color Changer':
    case 'LED Bar (Pixels)':
    case 'LED Bar (Beams)':
      return FixtureCategory.rgb;
    default:
      return FixtureCategory.generic;
  }
}

String qlcTypeForCategory(FixtureCategory category) => switch (category) {
  FixtureCategory.movingHead => 'Moving Head',
  FixtureCategory.rgb => 'Color Changer',
  FixtureCategory.generic => 'Other',
};

/// One channel of a parsed `.qxf`, before it's been placed in a mode.
class QlcChannel {
  final String name;
  final ChannelFunction function;
  final List<ChannelCapability> capabilities;

  const QlcChannel({required this.name, required this.function, required this.capabilities});
}

/// One DMX mode of a parsed `.qxf`.
class QlcMode {
  final String name;
  final List<QlcChannel> channels;

  const QlcMode({required this.name, required this.channels});
}

/// A whole parsed `.qxf` file.
class QlcFixture {
  final String manufacturer;
  final String model;
  final String type;
  final List<QlcMode> modes;

  const QlcFixture({
    required this.manufacturer,
    required this.model,
    required this.type,
    required this.modes,
  });

  FixtureCategory get category => categoryForQlcType(type);

  /// One [FixtureProfile] per mode — this app has no concept of modes, so a
  /// three-mode fixture becomes three profiles, each remembering which mode
  /// it came from so the pairing isn't lost.
  List<FixtureProfile> toProfiles() => [
    for (final mode in modes)
      FixtureProfile(
        id: 'imported',
        name: modes.length == 1 ? model : '$model ${mode.name}',
        category: category,
        manufacturer: manufacturer,
        model: model,
        modeName: mode.name,
        sourceFormat: 'qlcplus',
        channels: [
          for (var i = 0; i < mode.channels.length; i++)
            FixtureChannel(
              offset: i,
              function: mode.channels[i].function,
              customLabel: mode.channels[i].name == mode.channels[i].function.label
                  ? null
                  : mode.channels[i].name,
              capabilities: mode.channels[i].capabilities,
            ),
        ],
      ),
  ];
}

/// Parses one `.qxf` document. Throws [FormatException] if it isn't one.
QlcFixture parseQxf(String source) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(source);
  } catch (e) {
    throw FormatException('Not valid XML: $e');
  }
  final root = document.rootElement;
  if (root.name.local != 'FixtureDefinition') {
    throw const FormatException('Not a QLC+ fixture definition');
  }

  final manufacturer = root.getElement('Manufacturer')?.innerText.trim() ?? '';
  final model = root.getElement('Model')?.innerText.trim() ?? '';
  final type = root.getElement('Type')?.innerText.trim() ?? 'Other';
  if (model.isEmpty) throw const FormatException('Fixture definition has no model name');

  final channels = <String, QlcChannel>{};
  for (final element in root.findElements('Channel')) {
    final name = element.getAttribute('Name')?.trim() ?? '';
    if (name.isEmpty) continue;
    final preset = element.getAttribute('Preset');
    final group = element.getElement('Group')?.innerText.trim() ?? '';
    final capabilities = <ChannelCapability>[];
    for (final capability in element.findElements('Capability')) {
      final min = int.tryParse(capability.getAttribute('Min') ?? '');
      final max = int.tryParse(capability.getAttribute('Max') ?? '');
      final label = capability.innerText.trim();
      if (min == null || max == null || label.isEmpty) continue;
      capabilities.add(ChannelCapability(
        min: min,
        max: max,
        label: label,
        kind: (max - min) >= qlcRangeWidthThreshold ? CapabilityKind.range : CapabilityKind.slot,
      ));
    }
    channels[name] = QlcChannel(
      name: name,
      function: qlcPresetToFunction[preset] ?? functionFromGroupAndName(group, name),
      capabilities: normalizeCapabilities(capabilities),
    );
  }

  final modes = <QlcMode>[];
  for (final modeElement in root.findElements('Mode')) {
    // Channels carry an explicit Number; trust it over document order,
    // because a few definitions list them out of sequence.
    final entries = <int, String>{};
    for (final channelRef in modeElement.findElements('Channel')) {
      final number = int.tryParse(channelRef.getAttribute('Number') ?? '');
      final name = channelRef.innerText.trim();
      if (number == null || name.isEmpty) continue;
      entries[number] = name;
    }
    if (entries.isEmpty) continue;
    final ordered = entries.keys.toList()..sort();
    final modeChannels = [
      for (final index in ordered)
        if (channels[entries[index]!] != null) channels[entries[index]!]!,
    ];
    if (modeChannels.isEmpty) continue;
    final modeName = modeElement.getAttribute('Name')?.trim() ?? '';
    modes.add(QlcMode(
      name: modeName.isEmpty ? '${modeChannels.length}ch' : modeName,
      channels: modeChannels,
    ));
  }

  if (modes.isEmpty) throw const FormatException('Fixture definition has no usable DMX mode');
  return QlcFixture(manufacturer: manufacturer, model: model, type: type, modes: modes);
}

/// Writes [profile] as a `.qxf` document, so a fixture built here can be
/// opened in QLC+ or anything else that reads the format.
///
/// This app has one channel layout per profile, so the export always has
/// exactly one mode — round-tripping a multi-mode fixture through here
/// gives you one file per mode, not the original combined definition.
String writeQxf(FixtureProfile profile, {String creator = 'SmART DMX Controller'}) {
  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
  builder.element('FixtureDefinition', nest: () {
    builder.attribute('xmlns', 'http://www.qlcplus.org/FixtureDefinition');
    builder.element('Creator', nest: () {
      builder.element('Name', nest: creator);
      builder.element('Version', nest: '1.0');
      builder.element('Author', nest: '');
    });
    builder.element('Manufacturer', nest: profile.manufacturer ?? 'Custom');
    builder.element('Model', nest: profile.model ?? profile.name);
    builder.element('Type', nest: qlcTypeForCategory(profile.category));

    // QLC+ addresses channels by name, so they have to be unique within
    // the file even when two of ours share a label.
    final names = <String>[];
    final used = <String, int>{};
    for (final channel in profile.channels) {
      final base = channel.label;
      final seen = used.update(base, (n) => n + 1, ifAbsent: () => 1);
      names.add(seen == 1 ? base : '$base $seen');
    }

    for (var i = 0; i < profile.channels.length; i++) {
      final channel = profile.channels[i];
      builder.element('Channel', nest: () {
        builder.attribute('Name', names[i]);
        final preset = _functionToQlcPreset[channel.function];
        // A preset channel is self-describing in QLC+; anything else needs
        // an explicit group, and capabilities can't ride along with a
        // preset, so those force the long form too.
        if (preset != null && channel.capabilities.isEmpty) {
          builder.attribute('Preset', preset);
          return;
        }
        builder.element('Group', nest: () {
          builder.attribute('Byte', '0');
          builder.text(qlcGroupFor(channel.function));
        });
        for (final capability in channel.capabilities) {
          builder.element('Capability', nest: () {
            builder.attribute('Min', '${capability.min}');
            builder.attribute('Max', '${capability.max}');
            builder.text(capability.label);
          });
        }
      });
    }

    builder.element('Mode', nest: () {
      builder.attribute('Name', profile.modeName ?? '${profile.channels.length}ch');
      for (var i = 0; i < names.length; i++) {
        builder.element('Channel', nest: () {
          builder.attribute('Number', '$i');
          builder.text(names[i]);
        });
      }
    });
  });
  return builder.buildDocument().toXmlString(pretty: true, indent: ' ');
}
