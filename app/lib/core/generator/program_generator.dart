import 'dart:math';

import '../../models/channel_function.dart';
import '../../models/chase.dart';
import '../../models/patched_fixture.dart';
import '../../models/scene.dart';

enum GeneratorEffect {
  // Colour effects.
  staticColors,
  fadeTransition,
  colorChase,
  runningLight,
  strobe,
  rainbow,
  circle,
  disco,
  carousel,
  sparkle,
  randomColors,
  // Beam-movement effects (need pan/tilt fixtures to show their shape;
  // colour still applies so RGB fixtures aren't left dark).
  panSweep,
  tiltSweep,
  sweep,
  swim,
  float,
  center,
  lightRider,
}

extension GeneratorEffectLabel on GeneratorEffect {
  String get label {
    switch (this) {
      case GeneratorEffect.staticColors:
        return 'Static Colors';
      case GeneratorEffect.fadeTransition:
        return 'Fade Transition';
      case GeneratorEffect.colorChase:
        return 'Color Chase';
      case GeneratorEffect.runningLight:
        return 'Running Light';
      case GeneratorEffect.strobe:
        return 'Strobe / Pulse';
      case GeneratorEffect.rainbow:
        return 'Rainbow Sweep';
      case GeneratorEffect.disco:
        return 'Disco';
      case GeneratorEffect.carousel:
        return 'Carousel';
      case GeneratorEffect.sparkle:
        return 'Sparkle';
      case GeneratorEffect.randomColors:
        return 'Random';
      case GeneratorEffect.circle:
        return 'Circle';
      case GeneratorEffect.panSweep:
        return 'Pan';
      case GeneratorEffect.tiltSweep:
        return 'Tilt';
      case GeneratorEffect.sweep:
        return 'Sweep';
      case GeneratorEffect.swim:
        return 'Swim';
      case GeneratorEffect.float:
        return 'Float';
      case GeneratorEffect.center:
        return 'Center';
      case GeneratorEffect.lightRider:
        return 'Light Rider';
    }
  }

  /// Beam-movement effects — the ones Size/Fan/Shift shape, and the ones
  /// that need pan/tilt fixtures to look like anything.
  bool get isMove {
    switch (this) {
      case GeneratorEffect.circle:
      case GeneratorEffect.panSweep:
      case GeneratorEffect.tiltSweep:
      case GeneratorEffect.sweep:
      case GeneratorEffect.swim:
      case GeneratorEffect.float:
      case GeneratorEffect.center:
      case GeneratorEffect.lightRider:
        return true;
      default:
        return false;
    }
  }

  /// Sensible default playback timing for this effect, used when the
  /// generated scenes are dropped into a bank/chase step.
  (double hold, double fade) get defaultTiming {
    switch (this) {
      case GeneratorEffect.staticColors:
        return (2.0, 0.5);
      case GeneratorEffect.fadeTransition:
        return (1.0, 1.0);
      case GeneratorEffect.colorChase:
        return (0.3, 0.1);
      case GeneratorEffect.runningLight:
        return (0.12, 0.08);
      case GeneratorEffect.strobe:
        return (0.08, 0.0);
      case GeneratorEffect.rainbow:
        return (0.5, 0.5);
      case GeneratorEffect.disco:
        return (0.25, 0.05);
      case GeneratorEffect.carousel:
        return (0.4, 0.3);
      case GeneratorEffect.sparkle:
        return (0.12, 0.05);
      case GeneratorEffect.randomColors:
        return (0.5, 0.25);
      case GeneratorEffect.circle:
        return (0.15, 0.15);
      case GeneratorEffect.panSweep:
      case GeneratorEffect.tiltSweep:
      case GeneratorEffect.sweep:
        return (0.15, 0.15);
      case GeneratorEffect.swim:
        return (0.2, 0.2);
      case GeneratorEffect.float:
        return (0.6, 0.6);
      case GeneratorEffect.center:
        return (1.0, 0.8);
      case GeneratorEffect.lightRider:
        return (0.12, 0.08);
    }
  }
}

/// Which fixtures actually light up in each generated scene — an effect's
/// color/motion can still apply to just some of them instead of always
/// every patched fixture at once.
enum FixturePattern { all, alternating, oneAtATime, randomSubset }

extension FixturePatternLabel on FixturePattern {
  String get label {
    switch (this) {
      case FixturePattern.all:
        return 'All Together';
      case FixturePattern.alternating:
        return 'Alternating';
      case FixturePattern.oneAtATime:
        return 'One at a Time';
      case FixturePattern.randomSubset:
        return 'Random Subset';
    }
  }
}

List<bool> _activeMaskFor(FixturePattern pattern, int fixtureCount, int sceneIndex, Random random) {
  switch (pattern) {
    case FixturePattern.all:
      return List<bool>.filled(fixtureCount, true);
    case FixturePattern.alternating:
      final groupA = sceneIndex.isEven;
      return [for (var i = 0; i < fixtureCount; i++) i.isEven == groupA];
    case FixturePattern.oneAtATime:
      return [for (var i = 0; i < fixtureCount; i++) i == sceneIndex % fixtureCount];
    case FixturePattern.randomSubset:
      final mask = [for (var i = 0; i < fixtureCount; i++) random.nextBool()];
      // Never generate an all-dark scene by accident.
      if (!mask.contains(true)) mask[random.nextInt(fixtureCount)] = true;
      return mask;
  }
}

/// Zeroes out fixtures the current pattern says shouldn't light up this
/// scene — via their dimmer channel where they have one, else by zeroing
/// their color channels directly.
void _applyPatternMask(
  Map<String, List<int>> fixtureValues,
  List<PatchedFixture> fixtures,
  List<bool> mask,
) {
  for (var i = 0; i < fixtures.length; i++) {
    if (mask[i]) continue;
    final fixture = fixtures[i];
    final values = fixtureValues[fixture.id];
    if (values == null) continue;
    final channels = fixture.profile.channels;
    final dimmerIdx = channels.indexWhere((c) => c.function == ChannelFunction.dimmer);
    if (dimmerIdx != -1) {
      values[dimmerIdx] = 0;
    } else {
      for (var c = 0; c < channels.length; c++) {
        if (channels[c].function.isColorMix) values[c] = 0;
      }
    }
  }
}

List<int> _hsvToRgb(double hue, double saturation, double value) {
  final c = value * saturation;
  final x = c * (1 - ((hue / 60) % 2 - 1).abs());
  final m = value - c;
  double r1, g1, b1;
  if (hue < 60) {
    r1 = c;
    g1 = x;
    b1 = 0;
  } else if (hue < 120) {
    r1 = x;
    g1 = c;
    b1 = 0;
  } else if (hue < 180) {
    r1 = 0;
    g1 = c;
    b1 = x;
  } else if (hue < 240) {
    r1 = 0;
    g1 = x;
    b1 = c;
  } else if (hue < 300) {
    r1 = x;
    g1 = 0;
    b1 = c;
  } else {
    r1 = c;
    g1 = 0;
    b1 = x;
  }
  return [
    ((r1 + m) * 255).round().clamp(0, 255),
    ((g1 + m) * 255).round().clamp(0, 255),
    ((b1 + m) * 255).round().clamp(0, 255),
  ];
}

/// One fixture's channel values: colour (scaled by [brightness]) plus an
/// optional beam position. Channels the effect says nothing about stay at 0.
List<int> _channelValues(
  PatchedFixture fixture, {
  List<int>? rgb,
  int? pan,
  int? tilt,
  double brightness = 1.0,
}) {
  final channels = fixture.profile.channels;
  final values = List<int>.filled(channels.length, 0);
  int scaled(int component) => (component * brightness).round().clamp(0, 255);
  for (var i = 0; i < channels.length; i++) {
    switch (channels[i].function) {
      case ChannelFunction.red:
        if (rgb != null) values[i] = scaled(rgb[0]);
        break;
      case ChannelFunction.green:
        if (rgb != null) values[i] = scaled(rgb[1]);
        break;
      case ChannelFunction.blue:
        if (rgb != null) values[i] = scaled(rgb[2]);
        break;
      case ChannelFunction.dimmer:
        values[i] = scaled(255);
        break;
      case ChannelFunction.pan:
        if (pan != null) values[i] = pan;
        break;
      case ChannelFunction.tilt:
        if (tilt != null) values[i] = tilt;
        break;
      default:
        break;
    }
  }
  return values;
}

Map<String, List<int>> _colorValuesFor(
  List<PatchedFixture> fixtures,
  List<int> Function(PatchedFixture fixture) colorPicker,
) {
  final result = <String, List<int>>{};
  for (final fixture in fixtures) {
    result[fixture.id] = _channelValues(fixture, rgb: colorPicker(fixture));
  }
  return result;
}

/// -1 → 1 → -1 at a constant rate, unlike a sine's slow turnarounds.
double _triangle(double phase) => 4 * (phase - (phase + 0.5).floorToDouble()).abs() - 1;

/// Normalised beam position (-1..1 per axis) at [phase] (0..1 of one full
/// cycle) — the raw shape, before Size/Fan are applied.
(double pan, double tilt) _moveShape(GeneratorEffect effect, double phase) {
  final t = 2 * pi * phase;
  switch (effect) {
    case GeneratorEffect.circle:
      return (cos(t), sin(t));
    case GeneratorEffect.panSweep:
      return (sin(t), 0);
    case GeneratorEffect.tiltSweep:
      return (0, sin(t));
    case GeneratorEffect.sweep:
    case GeneratorEffect.lightRider:
      return (_triangle(phase), 0);
    case GeneratorEffect.swim:
      // Figure-eight: tilt runs at double rate against the pan swing.
      return (sin(t), sin(2 * t) * 0.6);
    case GeneratorEffect.float:
      // Two detuned sines per axis, so it wanders instead of repeating an
      // obvious geometric path.
      return (sin(t) * 0.6 + sin(3 * t) * 0.25, cos(2 * t) * 0.45);
    case GeneratorEffect.center:
      return (0, 0);
    default:
      return (0, 0);
  }
}

/// Builds [count] scenes for [fixtures] according to [effect], cycling
/// through [colors] where relevant. [pattern] decides which fixtures
/// actually light up in each scene (default: all of them at once). Pass
/// [idGenerator] to mint each scene's id (e.g. a uuid generator).
///
/// [size], [fan] and [shift] are the live FX shape controls, mirroring what
/// a busking app gives you on a fader: [size] scales how far the beams
/// travel from centre, [fan] spreads the rig outward in pan (first fixture
/// left, last one right), and [shift] walks each fixture along the cycle so
/// the effect ripples across the rig instead of every head moving as one.
/// [shift] also staggers the palette on colour effects.
List<Scene> generateScenes({
  required GeneratorEffect effect,
  required List<List<int>> colors,
  required List<PatchedFixture> fixtures,
  required int count,
  required String Function() idGenerator,
  required String namePrefix,
  FixturePattern pattern = FixturePattern.all,
  double size = 1.0,
  double fan = 0.0,
  double shift = 0.0,
}) {
  if (fixtures.isEmpty || count <= 0) return [];
  final palette = colors.isEmpty ? const [
    [255, 255, 255],
  ] : colors;
  final scenes = <Scene>[];
  final random = Random();

  void addScene(int index, Map<String, List<int>> fixtureValues) {
    if (pattern != FixturePattern.all) {
      _applyPatternMask(fixtureValues, fixtures, _activeMaskFor(pattern, fixtures.length, index, random));
    }
    scenes.add(Scene(id: idGenerator(), name: '$namePrefix ${index + 1}', fixtureValues: fixtureValues));
  }

  if (effect.isMove) {
    for (var i = 0; i < count; i++) {
      final map = <String, List<int>>{};
      for (var f = 0; f < fixtures.length; f++) {
        final fixture = fixtures[f];
        final phase = (i / count + shift * f / fixtures.length) % 1.0;
        final (rawPan, rawTilt) = _moveShape(effect, phase);
        // Fan spreads the rig outward around its middle fixture.
        final spread = fixtures.length <= 1 ? 0.0 : (f / (fixtures.length - 1)) * 2 - 1;
        final panNorm = (rawPan * size + spread * fan).clamp(-1.0, 1.0);
        final tiltNorm = (rawTilt * size).clamp(-1.0, 1.0);

        var brightness = 1.0;
        if (effect == GeneratorEffect.lightRider) {
          // The namesake scanner: only the beam the sweep is currently
          // passing over stays lit, the ones behind it fade out.
          final head = (_triangle(i / count) + 1) / 2 * (fixtures.length - 1);
          final tail = max(1.0, fixtures.length / 3);
          brightness = (1 - (f - head).abs() / tail).clamp(0.0, 1.0);
        }

        map[fixture.id] = _channelValues(
          fixture,
          rgb: palette[(i + (shift * f).round()) % palette.length],
          pan: (128 + 127 * panNorm).round().clamp(0, 255),
          tilt: (128 + 127 * tiltNorm).round().clamp(0, 255),
          brightness: brightness,
        );
      }
      addScene(i, map);
    }
    return scenes;
  }

  switch (effect) {
    case GeneratorEffect.staticColors:
    case GeneratorEffect.fadeTransition:
      for (var i = 0; i < count; i++) {
        final color = palette[i % palette.length];
        addScene(i, _colorValuesFor(fixtures, (_) => color));
      }
      break;

    case GeneratorEffect.colorChase:
      for (var i = 0; i < count; i++) {
        final activeIndex = i % fixtures.length;
        final color = palette[i % palette.length];
        addScene(
          i,
          _colorValuesFor(fixtures, (f) {
            return fixtures.indexOf(f) == activeIndex ? color : const [0, 0, 0];
          }),
        );
      }
      break;

    case GeneratorEffect.runningLight:
      // A moving "head" fixture with a fading comet tail behind it, like a
      // classic marquee/running-light chase — as opposed to Color Chase's
      // single fixture snapping on and off.
      final tailLength = max(2, (fixtures.length / 4).round());
      for (var i = 0; i < count; i++) {
        final headIndex = i % fixtures.length;
        final color = palette[i % palette.length];
        final map = <String, List<int>>{};
        for (var f = 0; f < fixtures.length; f++) {
          final fixture = fixtures[f];
          final distance = (headIndex - f) % fixtures.length;
          final behind = distance < 0 ? distance + fixtures.length : distance;
          final brightness = behind >= tailLength ? 0.0 : 1.0 - (behind / tailLength);
          map[fixture.id] = _channelValues(fixture, rgb: color, brightness: brightness);
        }
        addScene(i, map);
      }
      break;

    case GeneratorEffect.strobe:
      final color = palette.first;
      for (var i = 0; i < count; i++) {
        final on = i.isEven;
        addScene(i, _colorValuesFor(fixtures, (_) => on ? color : const [0, 0, 0]));
      }
      break;

    case GeneratorEffect.rainbow:
      for (var i = 0; i < count; i++) {
        final hue = 360 * i / count;
        final rgb = _hsvToRgb(hue, 1, 1);
        addScene(i, _colorValuesFor(fixtures, (_) => rgb));
      }
      break;

    case GeneratorEffect.disco:
      // Every fixture its own colour, re-rolled each scene — the busy
      // multi-colour party look.
      for (var i = 0; i < count; i++) {
        addScene(i, _colorValuesFor(fixtures, (_) => palette[random.nextInt(palette.length)]));
      }
      break;

    case GeneratorEffect.carousel:
      // The palette rotates around the rig: each fixture hands its colour
      // to its neighbour every scene.
      for (var i = 0; i < count; i++) {
        addScene(
          i,
          _colorValuesFor(fixtures, (f) => palette[(fixtures.indexOf(f) + i) % palette.length]),
        );
      }
      break;

    case GeneratorEffect.sparkle:
      // A dark rig with a few fixtures popping at full — glitter, not chase.
      for (var i = 0; i < count; i++) {
        final lit = max(1, (fixtures.length / 4).round());
        final chosen = <int>{};
        while (chosen.length < lit) {
          chosen.add(random.nextInt(fixtures.length));
        }
        final map = <String, List<int>>{};
        for (var f = 0; f < fixtures.length; f++) {
          map[fixtures[f].id] = _channelValues(
            fixtures[f],
            rgb: palette[random.nextInt(palette.length)],
            brightness: chosen.contains(f) ? 1.0 : 0.0,
          );
        }
        addScene(i, map);
      }
      break;

    case GeneratorEffect.randomColors:
      // One random colour at a time, whole rig together.
      for (var i = 0; i < count; i++) {
        final color = palette[random.nextInt(palette.length)];
        addScene(i, _colorValuesFor(fixtures, (_) => color));
      }
      break;

    // Movement effects are handled above, before this switch.
    case GeneratorEffect.circle:
    case GeneratorEffect.panSweep:
    case GeneratorEffect.tiltSweep:
    case GeneratorEffect.sweep:
    case GeneratorEffect.swim:
    case GeneratorEffect.float:
    case GeneratorEffect.center:
    case GeneratorEffect.lightRider:
      break;
  }
  return scenes;
}

/// A chase step referencing a whole bank, timed for [effect].
ChaseStep bankStepFor(GeneratorEffect effect, String bankId) {
  final (hold, fade) = effect.defaultTiming;
  return ChaseStep(
    bankId: bankId,
    hold: Duration(milliseconds: (hold * 1000).round()),
    fade: Duration(milliseconds: (fade * 1000).round()),
  );
}
