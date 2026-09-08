import 'dart:math';

import '../../models/channel_function.dart';
import '../../models/chase.dart';
import '../../models/patched_fixture.dart';
import '../../models/scene.dart';

enum GeneratorEffect { staticColors, fadeTransition, colorChase, strobe, rainbow, circle }

extension GeneratorEffectLabel on GeneratorEffect {
  String get label {
    switch (this) {
      case GeneratorEffect.staticColors:
        return 'Static Colors';
      case GeneratorEffect.fadeTransition:
        return 'Fade Transition';
      case GeneratorEffect.colorChase:
        return 'Color Chase';
      case GeneratorEffect.strobe:
        return 'Strobe / Pulse';
      case GeneratorEffect.rainbow:
        return 'Rainbow Sweep';
      case GeneratorEffect.circle:
        return 'Circle (Pan/Tilt)';
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
      case GeneratorEffect.strobe:
        return (0.08, 0.0);
      case GeneratorEffect.rainbow:
        return (0.5, 0.5);
      case GeneratorEffect.circle:
        return (0.15, 0.15);
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

Map<String, List<int>> _colorValuesFor(
  List<PatchedFixture> fixtures,
  List<int> Function(PatchedFixture fixture) colorPicker,
) {
  final result = <String, List<int>>{};
  for (final fixture in fixtures) {
    final channels = fixture.profile.channels;
    final values = List<int>.filled(channels.length, 0);
    final rgb = colorPicker(fixture);
    for (var i = 0; i < channels.length; i++) {
      switch (channels[i].function) {
        case ChannelFunction.red:
          values[i] = rgb[0];
          break;
        case ChannelFunction.green:
          values[i] = rgb[1];
          break;
        case ChannelFunction.blue:
          values[i] = rgb[2];
          break;
        case ChannelFunction.dimmer:
          values[i] = 255;
          break;
        default:
          break;
      }
    }
    result[fixture.id] = values;
  }
  return result;
}

/// Builds [count] scenes for [fixtures] according to [effect], cycling
/// through [colors] where relevant. Pass [idGenerator] to mint each scene's
/// id (e.g. a uuid generator).
List<Scene> generateScenes({
  required GeneratorEffect effect,
  required List<List<int>> colors,
  required List<PatchedFixture> fixtures,
  required int count,
  required String Function() idGenerator,
  required String namePrefix,
}) {
  if (fixtures.isEmpty || count <= 0) return [];
  final palette = colors.isEmpty ? const [
    [255, 255, 255],
  ] : colors;
  final scenes = <Scene>[];

  switch (effect) {
    case GeneratorEffect.staticColors:
    case GeneratorEffect.fadeTransition:
      for (var i = 0; i < count; i++) {
        final color = palette[i % palette.length];
        scenes.add(
          Scene(
            id: idGenerator(),
            name: '$namePrefix ${i + 1}',
            fixtureValues: _colorValuesFor(fixtures, (_) => color),
          ),
        );
      }
      break;

    case GeneratorEffect.colorChase:
      for (var i = 0; i < count; i++) {
        final activeIndex = i % fixtures.length;
        final color = palette[i % palette.length];
        scenes.add(
          Scene(
            id: idGenerator(),
            name: '$namePrefix ${i + 1}',
            fixtureValues: _colorValuesFor(fixtures, (f) {
              return fixtures.indexOf(f) == activeIndex ? color : const [0, 0, 0];
            }),
          ),
        );
      }
      break;

    case GeneratorEffect.strobe:
      final color = palette.first;
      for (var i = 0; i < count; i++) {
        final on = i.isEven;
        scenes.add(
          Scene(
            id: idGenerator(),
            name: '$namePrefix ${i + 1}',
            fixtureValues: _colorValuesFor(fixtures, (_) => on ? color : const [0, 0, 0]),
          ),
        );
      }
      break;

    case GeneratorEffect.rainbow:
      for (var i = 0; i < count; i++) {
        final hue = 360 * i / count;
        final rgb = _hsvToRgb(hue, 1, 1);
        scenes.add(
          Scene(
            id: idGenerator(),
            name: '$namePrefix ${i + 1}',
            fixtureValues: _colorValuesFor(fixtures, (_) => rgb),
          ),
        );
      }
      break;

    case GeneratorEffect.circle:
      for (var i = 0; i < count; i++) {
        final theta = 2 * pi * i / count;
        final pan = (128 + 100 * cos(theta)).round().clamp(0, 255);
        final tilt = (128 + 100 * sin(theta)).round().clamp(0, 255);
        final map = <String, List<int>>{};
        for (final fixture in fixtures) {
          final channels = fixture.profile.channels;
          final values = List<int>.filled(channels.length, 0);
          for (var c = 0; c < channels.length; c++) {
            switch (channels[c].function) {
              case ChannelFunction.pan:
                values[c] = pan;
                break;
              case ChannelFunction.tilt:
                values[c] = tilt;
                break;
              case ChannelFunction.dimmer:
                values[c] = 255;
                break;
              default:
                break;
            }
          }
          map[fixture.id] = values;
        }
        scenes.add(Scene(id: idGenerator(), name: '$namePrefix ${i + 1}', fixtureValues: map));
      }
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
