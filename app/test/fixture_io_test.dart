import 'package:dmx_controller/core/fixtures/fixture_io.dart';
import 'package:dmx_controller/core/fixtures/qlcplus_format.dart';
import 'package:dmx_controller/models/channel_capability.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real Chauvet definition, copied verbatim from the QLC+ library, so the
/// parser is tested against the shape the bundled assets are built from
/// rather than something invented to suit it.
const _chauvet200b = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE FixtureDefinition>
<FixtureDefinition xmlns="http://www.qlcplus.org/FixtureDefinition">
 <Creator>
  <Name>Q Light Controller Plus</Name>
  <Version>4.12.3 GIT</Version>
  <Author>Heikki Junnila</Author>
 </Creator>
 <Manufacturer>Chauvet</Manufacturer>
 <Model>200b</Model>
 <Type>Color Changer</Type>
 <Channel Name="Function">
  <Group Byte="0">Maintenance</Group>
  <Capability Min="0" Max="29">RGB</Capability>
  <Capability Min="30" Max="59">Pulse Strobe 0-100%</Capability>
  <Capability Min="240" Max="255">Sound activated</Capability>
 </Channel>
 <Channel Name="Red" Preset="IntensityRed"/>
 <Channel Name="Green" Preset="IntensityGreen"/>
 <Channel Name="Blue" Preset="IntensityBlue"/>
 <Channel Name="Strobe" Preset="ShutterStrobeSlowFast"/>
 <Channel Name="Dimmer" Preset="IntensityDimmer"/>
 <Mode Name="All">
  <Channel Number="0">Function</Channel>
  <Channel Number="1">Red</Channel>
  <Channel Number="2">Green</Channel>
  <Channel Number="3">Blue</Channel>
  <Channel Number="4">Strobe</Channel>
  <Channel Number="5">Dimmer</Channel>
 </Mode>
</FixtureDefinition>
''';

void main() {
  group('QLC+ import', () {
    test('reads the manufacturer, model and mode', () {
      final fixture = parseQxf(_chauvet200b);
      expect(fixture.manufacturer, 'Chauvet');
      expect(fixture.model, '200b');
      expect(fixture.type, 'Color Changer');
      expect(fixture.modes.single.name, 'All');
      expect(fixture.modes.single.channels.length, 6);
    });

    test('maps channel presets onto the app\'s functions', () {
      final channels = parseQxf(_chauvet200b).modes.single.channels;
      expect(channels[1].function, ChannelFunction.red);
      expect(channels[2].function, ChannelFunction.green);
      expect(channels[3].function, ChannelFunction.blue);
      expect(channels[4].function, ChannelFunction.strobe);
      expect(channels[5].function, ChannelFunction.dimmer);
    });

    test('a preset-less channel keeps its own name rather than being guessed at', () {
      // "Function" in QLC+'s Maintenance group could be an auto-program, a
      // reset or a lamp control — nothing in the file says which, so it
      // stays generic. What makes it usable is that the manufacturer's
      // channel name and its value ranges survive.
      final channel = parseQxf(_chauvet200b).modes.single.channels.first;
      expect(channel.function, ChannelFunction.generic);
      expect(channel.name, 'Function');
      expect(channel.capabilities, isNotEmpty);
    });

    test('the Effect group does map onto autofade', () {
      final source = _chauvet200b.replaceFirst(
        '<Group Byte="0">Maintenance</Group>',
        '<Group Byte="0">Effect</Group>',
      );
      expect(parseQxf(source).modes.single.channels.first.function, ChannelFunction.autofade);
    });

    test('capabilities come across with their labels and spans', () {
      final function = parseQxf(_chauvet200b).modes.single.channels.first;
      expect(function.capabilities.length, 3);
      expect(function.capabilities.first.label, 'RGB');
      expect(function.capabilities.first.min, 0);
      expect(function.capabilities.first.max, 29);
      // Wide spans are treated as something you fine-tune, narrow ones as a
      // fixed choice.
      expect(function.capabilities.first.kind, CapabilityKind.range);
      expect(function.capabilities.last.kind, CapabilityKind.slot);
    });

    test('a mode becomes a profile that remembers where it came from', () {
      final profile = parseQxf(_chauvet200b).toProfiles().single;
      expect(profile.manufacturer, 'Chauvet');
      expect(profile.model, '200b');
      expect(profile.modeName, 'All');
      expect(profile.sourceFormat, 'qlcplus');
      expect(profile.channels.first.offset, 0);
      expect(profile.channels.last.offset, 5);
    });

    test('channels are ordered by their Number, not document order', () {
      final scrambled = _chauvet200b.replaceFirst(
        '  <Channel Number="0">Function</Channel>\n  <Channel Number="1">Red</Channel>',
        '  <Channel Number="1">Red</Channel>\n  <Channel Number="0">Function</Channel>',
      );
      final channels = parseQxf(scrambled).modes.single.channels;
      expect(channels.first.name, 'Function');
      expect(channels[1].name, 'Red');
    });

    test('something that is not a fixture definition is rejected clearly', () {
      expect(() => parseQxf('<html><body>nope</body></html>'), throwsFormatException);
      expect(() => parseQxf('not xml at all'), throwsFormatException);
    });
  });

  group('QLC+ export', () {
    const profile = FixtureProfile(
      id: 'p',
      name: 'Test Par',
      category: FixtureCategory.rgb,
      manufacturer: 'Acme',
      model: 'Test Par',
      modeName: '5ch',
      channels: [
        FixtureChannel(offset: 0, function: ChannelFunction.dimmer),
        FixtureChannel(offset: 1, function: ChannelFunction.red),
        FixtureChannel(offset: 2, function: ChannelFunction.green),
        FixtureChannel(offset: 3, function: ChannelFunction.blue),
        FixtureChannel(
          offset: 4,
          function: ChannelFunction.strobe,
          capabilities: [
            ChannelCapability(min: 0, max: 3, label: 'Closed', kind: CapabilityKind.off),
            ChannelCapability(min: 4, max: 255, label: 'Strobe', kind: CapabilityKind.range),
          ],
        ),
      ],
    );

    test('what we write, we can read back', () {
      final reparsed = parseQxf(writeQxf(profile));
      expect(reparsed.manufacturer, 'Acme');
      expect(reparsed.model, 'Test Par');
      expect(reparsed.modes.single.name, '5ch');
      final channels = reparsed.modes.single.channels;
      expect(channels.map((c) => c.function).toList(), [
        ChannelFunction.dimmer,
        ChannelFunction.red,
        ChannelFunction.green,
        ChannelFunction.blue,
        ChannelFunction.strobe,
      ]);
      expect(channels.last.capabilities.map((c) => c.label).toList(), ['Closed', 'Strobe']);
    });

    test('duplicate channel labels are made unique — QLC+ addresses by name', () {
      const twoGenerics = FixtureProfile(
        id: 'p',
        name: 'Odd',
        category: FixtureCategory.generic,
        channels: [
          FixtureChannel(offset: 0, function: ChannelFunction.generic),
          FixtureChannel(offset: 1, function: ChannelFunction.generic),
        ],
      );
      final reparsed = parseQxf(writeQxf(twoGenerics));
      final names = reparsed.modes.single.channels.map((c) => c.name).toList();
      expect(names.toSet().length, 2, reason: 'both channels survived as distinct entries');
    });
  });

  group('JSON and CSV', () {
    const profile = FixtureProfile(
      id: 'p',
      name: 'Club Par',
      category: FixtureCategory.rgb,
      channels: [
        FixtureChannel(offset: 0, function: ChannelFunction.dimmer),
        FixtureChannel(offset: 1, function: ChannelFunction.red),
        FixtureChannel(
          offset: 2,
          function: ChannelFunction.autofade,
          customLabel: 'Auto programs',
          capabilities: [
            ChannelCapability(min: 0, max: 9, label: 'Off', kind: CapabilityKind.off),
            ChannelCapability(min: 10, max: 200, label: 'Fade, slow to fast', kind: CapabilityKind.range),
            ChannelCapability(min: 201, max: 255, label: 'Sound active', kind: CapabilityKind.range),
          ],
        ),
      ],
    );

    test('JSON export round-trips losslessly', () {
      final result = importFixtures('fixtures.json', exportFixturesJson([profile]));
      final restored = result.profiles.single;
      expect(restored.name, 'Club Par');
      expect(restored.channels.length, 3);
      expect(restored.channels.last.customLabel, 'Auto programs');
      expect(restored.channels.last.capabilities.length, 3);
      expect(restored.channels.last.capabilities[1].label, 'Fade, slow to fast');
    });

    test('CSV survives a round trip, comma in a range label included', () {
      final csv = exportFixturesCsv([profile]);
      final restored = importFixtures('fixtures.csv', csv).profiles.single;
      expect(restored.name, 'Club Par');
      expect(restored.channels.length, 3);
      expect(restored.channels.last.function, ChannelFunction.autofade);
      expect(restored.channels.last.customLabel, 'Auto programs');
      expect(
        restored.channels.last.capabilities.map((c) => c.label).toList(),
        ['Off', 'Fade, slow to fast', 'Sound active'],
      );
    });

    test('a hand-written CSV with no ranges still imports', () {
      final result = importFixtures('chart.csv', [
        'fixture,channel,function,label,ranges',
        'My Par,1,dimmer,,',
        'My Par,2,red,,',
        'My Par,3,green,,',
      ].join('\n'));
      final profile = result.profiles.single;
      expect(profile.channels.length, 3);
      expect(profile.category, FixtureCategory.rgb, reason: 'guessed from the colour channels');
      expect(profile.channels.every((c) => c.capabilities.isEmpty), isTrue);
    });

    test('a project export can be used as a fixture source', () {
      final result = importFixtures('show.json', '{"name":"Show","fixtureProfiles":'
          '[{"id":"x","name":"From project","category":"rgb","channels":'
          '[{"offset":0,"function":"dimmer"}]}]}');
      expect(result.profiles.single.name, 'From project');
    });

    test('an unknown extension is refused rather than guessed at', () {
      expect(() => importFixtures('thing.gdtf', 'anything'), throwsFormatException);
    });

    test('an empty or unreadable file reports why', () {
      expect(() => importFixtures('empty.csv', '   '), throwsFormatException);
      expect(() => importFixtures('bad.json', '{oops'), throwsFormatException);
      expect(() => importFixtures('none.json', '{"fixtures":[]}'), throwsFormatException);
    });
  });
}
