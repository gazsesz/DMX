import 'dart:typed_data';

import 'package:flutter/painting.dart' show Color;

import '../../models/channel_capability.dart';
import '../../models/channel_function.dart';
import '../../models/patched_fixture.dart';
import '../../models/universe_config.dart';
import '../widgets/wheel_looks.dart';

/// One of the basic colours the live Colour strip can lay over the show.
class LiveColor {
  final String id;
  final String label;
  final int r;
  final int g;
  final int b;

  const LiveColor(this.id, this.label, this.r, this.g, this.b);

  bool get isWhite => r == 255 && g == 255 && b == 255;

  Color get swatch => Color.fromARGB(255, r, g, b);
}

/// What a moving head's colour wheel and an RGB par can both do, in the order
/// the strip shows them. Deliberately few: this is the "change it now" row,
/// the colour picker is for building looks.
const liveColors = <LiveColor>[
  LiveColor('red', 'Red', 255, 0, 0),
  LiveColor('orange', 'Orange', 255, 110, 0),
  LiveColor('yellow', 'Yellow', 255, 200, 0),
  LiveColor('green', 'Green', 0, 255, 0),
  LiveColor('cyan', 'Cyan', 0, 255, 255),
  LiveColor('blue', 'Blue', 0, 0, 255),
  LiveColor('purple', 'Purple', 140, 0, 255),
  LiveColor('magenta', 'Magenta', 255, 0, 255),
  LiveColor('white', 'White', 255, 255, 255),
];

/// The [liveColors] entry called [name] (id or label, any case), or null.
LiveColor? liveColorNamed(String name) {
  final wanted = name.trim().toLowerCase();
  for (final color in liveColors) {
    if (color.id == wanted || color.label.toLowerCase() == wanted) return color;
  }
  return null;
}

/// A custom colour from `RRGGBB` or `#RRGGBB`, or null when [hex] isn't one.
LiveColor? liveColorFromHex(String hex) {
  final cleaned = hex.trim().replaceFirst('#', '');
  if (cleaned.length != 6) return null;
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return null;
  return LiveColor('#${cleaned.toLowerCase()}', '#${cleaned.toUpperCase()}', (value >> 16) & 255, (value >> 8) & 255, value & 255);
}

/// How one fixture takes a live colour: the emitters to drive, and the wheel
/// slot to park on. Worked out once when a colour is picked, so applying it to
/// a frame is a handful of writes.
class FixtureColorPatch {
  final int? red;
  final int? green;
  final int? blue;
  final int? white;
  final int? amber;
  final int? uv;

  /// True when the fixture has its own dimmer. Without one the emitters *are*
  /// the intensity, so the colour is laid over at the level the show already
  /// had them — a dark par stays dark instead of lighting up.
  final bool hasDimmer;

  final int? wheel;
  final int wheelValue;

  const FixtureColorPatch({
    this.red,
    this.green,
    this.blue,
    this.white,
    this.amber,
    this.uv,
    this.hasDimmer = false,
    this.wheel,
    this.wheelValue = 0,
  });

  bool get isEmpty => red == null && green == null && blue == null && wheel == null;
}

bool _inUniverse(int address) => address >= 0 && address <= 511;

/// The wheel value of the single-colour slot closest to [color], or null when
/// the wheel has no slot with a known colour. Split colours are skipped: a
/// half red / half blue slot is not "blue".
int? nearestWheelValue(List<ChannelCapability> capabilities, LiveColor color) {
  int? best;
  var bestDistance = double.infinity;
  for (final capability in capabilities) {
    if (capability.kind == CapabilityKind.range) continue;
    final colors = wheelColorsFor(capability);
    if (colors == null || colors.length != 1) continue;
    final c = colors.first;
    final dr = (c.r * 255 - color.r).toDouble();
    final dg = (c.g * 255 - color.g).toDouble();
    final db = (c.b * 255 - color.b).toDouble();
    final distance = dr * dr + dg * dg + db * db;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = capability.pickValue;
    }
  }
  return best;
}

/// Per universe id, how each of [fixtures] (limited to [only] when given)
/// takes [color]. Fixtures with neither emitters nor a usable wheel are left
/// out, so they keep whatever the show gives them.
Map<String, List<FixtureColorPatch>> colorPatchesFor(
  List<PatchedFixture> fixtures,
  List<UniverseConfig> universes,
  LiveColor color, {
  Set<String>? only,
}) {
  final known = {for (final universe in universes) universe.id};
  final result = <String, List<FixtureColorPatch>>{};

  for (final fixture in fixtures) {
    if (only != null && !only.contains(fixture.id)) continue;
    if (!known.contains(fixture.universeId)) continue;

    int? at(ChannelFunction function) {
      for (final channel in fixture.profile.channels) {
        if (channel.function != function) continue;
        final address = fixture.startChannel + channel.offset;
        return _inUniverse(address) ? address : null;
      }
      return null;
    }

    int? wheel;
    var wheelValue = 0;
    for (final channel in fixture.profile.channels) {
      if (channel.function != ChannelFunction.colorWheel || channel.capabilities.isEmpty) continue;
      final value = nearestWheelValue(channel.capabilities, color);
      final address = fixture.startChannel + channel.offset;
      if (value != null && _inUniverse(address)) {
        wheel = address;
        wheelValue = value;
        break;
      }
    }

    final patch = FixtureColorPatch(
      red: at(ChannelFunction.red),
      green: at(ChannelFunction.green),
      blue: at(ChannelFunction.blue),
      white: at(ChannelFunction.white),
      amber: at(ChannelFunction.amber),
      uv: at(ChannelFunction.uv),
      hasDimmer: fixture.profile.channels.any((c) => c.function.isDimmer),
      wheel: wheel,
      wheelValue: wheelValue,
    );
    if (patch.isEmpty) continue;
    result.putIfAbsent(fixture.universeId, () => []).add(patch);
  }
  return result;
}

/// [frame] with [color] laid over the colour channels of [patches].
///
/// Colour only: a fixture's dimmer, position, gobo and everything else go out
/// as the show wrote them. Returns [frame] itself when there is nothing to
/// patch and never writes into it.
Uint8List applyColorOverride(Uint8List frame, List<FixtureColorPatch> patches, LiveColor color) {
  if (patches.isEmpty) return frame;
  final out = Uint8List.fromList(frame);

  int at(int? address) => address == null || address >= frame.length ? 0 : frame[address];
  void put(int? address, int value) {
    if (address != null && address < out.length) out[address] = value;
  }

  for (final patch in patches) {
    var r = color.r;
    var g = color.g;
    var b = color.b;
    // A fixture with no dimmer: keep the level the show had, take the hue.
    if (!patch.hasDimmer && (patch.red != null || patch.green != null || patch.blue != null)) {
      final level = [at(patch.red), at(patch.green), at(patch.blue), at(patch.white)].reduce((a, b) => a > b ? a : b);
      if (level == 0) {
        // Dark stays dark; only the wheel (if any) is repositioned.
        if (patch.wheel != null) put(patch.wheel, patch.wheelValue);
        continue;
      }
      r = r * level ~/ 255;
      g = g * level ~/ 255;
      b = b * level ~/ 255;
    }
    put(patch.red, r);
    put(patch.green, g);
    put(patch.blue, b);
    // White gets the white emitter too; any other colour must not be washed
    // out by it.
    put(patch.white, color.isWhite ? (patch.hasDimmer ? 255 : (r > g ? (r > b ? r : b) : (g > b ? g : b))) : 0);
    put(patch.amber, 0);
    put(patch.uv, 0);
    if (patch.wheel != null) put(patch.wheel, patch.wheelValue);
  }
  return out;
}
