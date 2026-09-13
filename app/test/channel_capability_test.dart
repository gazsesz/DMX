import 'package:dmx_controller/models/builtin_fixtures.dart';
import 'package:dmx_controller/models/channel_capability.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Value ranges are what let a fader say "Strobe slow→fast" instead of
/// "180", so the lookup, the round trip and the no-ranges fallback all have
/// to hold — a project saved before ranges existed must still load.
void main() {
  const strobe = [
    ChannelCapability(min: 0, max: 3, label: 'Closed', kind: CapabilityKind.off),
    ChannelCapability(min: 4, max: 7, label: 'Open'),
    ChannelCapability(min: 8, max: 215, label: 'Strobe', kind: CapabilityKind.range),
    ChannelCapability(min: 216, max: 255, label: 'Random', kind: CapabilityKind.range),
  ];

  test('a value resolves to the span containing it', () {
    const channel = FixtureChannel(offset: 0, function: ChannelFunction.strobe, capabilities: strobe);
    expect(channel.capabilityFor(0)?.label, 'Closed');
    expect(channel.capabilityFor(5)?.label, 'Open');
    expect(channel.capabilityFor(180)?.label, 'Strobe');
    expect(channel.capabilityFor(255)?.label, 'Random');
  });

  test('a gap in the ranges resolves to nothing rather than the nearest guess', () {
    const channel = FixtureChannel(
      offset: 0,
      function: ChannelFunction.generic,
      capabilities: [ChannelCapability(min: 0, max: 9, label: 'Off')],
    );
    expect(channel.capabilityFor(10), isNull);
  });

  test('picking a slot lands mid-span, picking a range lands at its bottom', () {
    // Mid-span keeps a gobo clear of its neighbours; the bottom of a range
    // is where you start before fine-tuning upwards.
    expect(const ChannelCapability(min: 8, max: 15, label: 'Gobo 1').pickValue, 11);
    expect(strobe[2].pickValue, 8);
  });

  test('capabilities survive a JSON round trip', () {
    const channel = FixtureChannel(offset: 2, function: ChannelFunction.strobe, capabilities: strobe);
    final restored = FixtureChannel.fromJson(channel.toJson());
    expect(restored.capabilities.length, 4);
    expect(restored.capabilities[2].label, 'Strobe');
    expect(restored.capabilities[2].kind, CapabilityKind.range);
    expect(restored.capabilities[2].min, 8);
    expect(restored.capabilities[2].max, 215);
  });

  test('a channel saved before ranges existed loads as a plain fader', () {
    final restored = FixtureChannel.fromJson({'offset': 0, 'function': 'dimmer'});
    expect(restored.capabilities, isEmpty);
    expect(restored.hasCapabilities, isFalse);
    // ...and writing it back doesn't invent an empty key.
    expect(restored.toJson().containsKey('capabilities'), isFalse);
  });

  test('normalising sorts by value and drops unlabelled or inverted spans', () {
    final normalized = normalizeCapabilities(const [
      ChannelCapability(min: 100, max: 200, label: 'Second'),
      ChannelCapability(min: 0, max: 99, label: '  First  '),
      ChannelCapability(min: 0, max: 10, label: ''),
      ChannelCapability(min: 50, max: 20, label: 'Backwards'),
    ]);
    expect([for (final c in normalized) c.label], ['First', 'Second']);
  });

  test('a profile with no gobo ranges falls back to the generic eight', () {
    expect(goboChoicesFor(const []).length, goboPresets.length);
    expect(goboLabelFor(const [], 0), 'Open');
    expect(goboLabelFor(const [], 70), goboPresets[2]);
  });

  test('a profile with gobo ranges uses its own names', () {
    const own = [
      ChannelCapability(min: 0, max: 7, label: 'No gobo'),
      ChannelCapability(min: 8, max: 15, label: 'Spiral'),
    ];
    expect(goboChoicesFor(own), own);
    expect(goboLabelFor(own, 12), 'Spiral');
  });

  test('import provenance survives a profile round trip', () {
    const profile = FixtureProfile(
      id: 'p1',
      name: 'Intimidator Spot 260',
      category: FixtureCategory.movingHead,
      channels: [FixtureChannel(offset: 0, function: ChannelFunction.dimmer)],
      manufacturer: 'Chauvet',
      model: 'Intimidator Spot 260',
      modeName: '12ch',
      sourceFormat: 'qxf',
    );
    final restored = FixtureProfile.fromJson(profile.toJson());
    expect(restored.manufacturer, 'Chauvet');
    expect(restored.modeName, '12ch');
    expect(restored.sourceFormat, 'qxf');
    expect(restored.qualifiedName, 'Chauvet Intimidator Spot 260 · 12ch');
  });
}
