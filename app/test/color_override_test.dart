import 'dart:typed_data';

import 'package:dmx_controller/core/playback/color_override.dart';
import 'package:dmx_controller/models/channel_capability.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/universe_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// The live colour is an output layer: it recolours, it never lights a dark
/// fixture and never touches anything that isn't colour.
void main() {
  const universe = UniverseConfig(id: 'u1', name: 'Universe 1', universe: 0);

  PatchedFixture patch(String id, List<FixtureChannel> channels, int start) => PatchedFixture(
    id: id,
    label: id,
    profile: FixtureProfile(id: id, name: id, category: FixtureCategory.generic, channels: channels),
    universeId: 'u1',
    startChannel: start,
  );

  FixtureChannel ch(int offset, ChannelFunction f, [List<ChannelCapability> caps = const []]) =>
      FixtureChannel(offset: offset, function: f, capabilities: caps);

  final rgbPar = patch('par', [ch(0, ChannelFunction.red), ch(1, ChannelFunction.green), ch(2, ChannelFunction.blue)], 0);
  final washWithDimmer = patch(
    'wash',
    [ch(0, ChannelFunction.dimmer), ch(1, ChannelFunction.red), ch(2, ChannelFunction.green), ch(3, ChannelFunction.blue)],
    10,
  );
  final head = patch(
    'head',
    [
      ch(0, ChannelFunction.pan),
      ch(1, ChannelFunction.colorWheel, const [
        ChannelCapability(min: 0, max: 9, label: 'Open'),
        ChannelCapability(min: 10, max: 19, label: 'Red'),
        ChannelCapability(min: 20, max: 29, label: 'Blue'),
        ChannelCapability(min: 30, max: 39, label: 'Red/Blue'),
      ]),
    ],
    20,
  );

  Uint8List run(List<PatchedFixture> fixtures, Map<int, int> values, LiveColor color, {Set<String>? only}) {
    final frame = Uint8List(512);
    values.forEach((c, v) => frame[c] = v);
    final patches = colorPatchesFor(fixtures, [universe], color, only: only)['u1'] ?? const [];
    return applyColorOverride(frame, patches, color);
  }

  final blue = liveColorNamed('blue')!;
  final red = liveColorNamed('red')!;

  test('an RGB par keeps the level the show had and takes the hue', () {
    final out = run([rgbPar], {0: 200, 1: 100, 2: 0}, blue);
    expect(out.sublist(0, 3), [0, 0, 200]);
  });

  test('a dark par stays dark', () {
    final out = run([rgbPar], {}, blue);
    expect(out.sublist(0, 3), [0, 0, 0]);
  });

  test('a fixture with a dimmer gets the full colour and its dimmer is left alone', () {
    final out = run([washWithDimmer], {10: 90, 11: 255}, blue);
    expect(out.sublist(10, 14), [90, 0, 0, 255]);
  });

  test('a colour wheel parks on the nearest single-colour slot and leaves pan alone', () {
    final out = run([head], {20: 123, 21: 0}, blue);
    expect(out[20], 123);
    expect(out[21], 24); // middle of the Blue slot (20-29)
  });

  test('the split slot is never picked for a plain colour', () {
    final out = run([head], {}, red);
    expect(out[21], 14); // middle of the Red slot (10-19)
  });

  test('white drives the white emitter, other colours switch it off', () {
    final rgbw = patch(
      'rgbw',
      [ch(0, ChannelFunction.dimmer), ch(1, ChannelFunction.red), ch(2, ChannelFunction.green), ch(3, ChannelFunction.blue), ch(4, ChannelFunction.white)],
      30,
    );
    expect(run([rgbw], {34: 200}, liveColorNamed('white')!).sublist(30, 35), [0, 255, 255, 255, 255]);
    expect(run([rgbw], {34: 200}, red)[34], 0);
  });

  test('only limits the colour to the chosen fixtures', () {
    final out = run([rgbPar, washWithDimmer], {0: 255, 11: 255}, blue, only: {'par'});
    expect(out.sublist(0, 3), [0, 0, 255]);
    expect(out[11], 255); // the wash was not in the group
  });

  test('never writes into the frame it was handed', () {
    final frame = Uint8List(512)..[0] = 255;
    final patches = colorPatchesFor([rgbPar], [universe], blue)['u1']!;
    applyColorOverride(frame, patches, blue);
    expect(frame[0], 255);
  });

  test('colour lookup by name and hex', () {
    expect(liveColorNamed('Magenta')!.id, 'magenta');
    expect(liveColorNamed('nope'), isNull);
    final hex = liveColorFromHex('#FF8800')!;
    expect([hex.r, hex.g, hex.b], [255, 136, 0]);
    expect(liveColorFromHex('xyz'), isNull);
  });
}
