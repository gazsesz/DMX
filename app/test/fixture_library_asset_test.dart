import 'package:dmx_controller/core/fixtures/fixture_library_asset.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reads the fixture library assets that actually ship, so a broken build
/// of them fails here rather than on stage. Regenerate them with
/// `dart run tool/build_fixture_library.dart <qlcplus>/resources/fixtures`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FixtureLibraryAsset asset;
  setUp(() => asset = FixtureLibraryAsset());

  test('the index lists every manufacturer with a fixture count', () async {
    final manufacturers = await asset.manufacturers();
    expect(manufacturers.length, greaterThan(100));
    expect(asset.fixtureCount, greaterThan(1500));
    expect(asset.modeCount, greaterThan(4000));
    expect(manufacturers.every((m) => m.fixtureCount > 0), isTrue);
    expect(manufacturers.every((m) => m.slug.isNotEmpty), isTrue);
    // Sorted case-insensitively, because the browser shows it as-is.
    final names = [for (final m in manufacturers) m.name.toLowerCase()];
    expect(names, orderedEquals(List.of(names)..sort()));
  });

  test('a manufacturer file opens and its fixtures carry modes', () async {
    final manufacturers = await asset.manufacturers();
    final chauvet = manufacturers.firstWhere((m) => m.name == 'Chauvet');
    final fixtures = await asset.fixturesOf(chauvet);
    expect(fixtures.length, chauvet.fixtureCount);
    expect(fixtures.every((f) => f.modes.isNotEmpty), isTrue);
    expect(fixtures.every((f) => f.modes.every((m) => m.channelCount > 0)), isTrue);
  });

  test('channel offsets are contiguous from zero in every mode', () async {
    final manufacturers = await asset.manufacturers();
    final fixtures = await asset.fixturesOf(manufacturers.firstWhere((m) => m.name == 'Chauvet'));
    for (final fixture in fixtures) {
      for (final mode in fixture.modes) {
        for (var i = 0; i < mode.channels.length; i++) {
          expect(mode.channels[i].offset, i, reason: '${fixture.model} / ${mode.name}');
        }
      }
    }
  });

  test('value ranges survived the build — this is the point of the library', () async {
    final manufacturers = await asset.manufacturers();
    final fixtures = await asset.fixturesOf(manufacturers.firstWhere((m) => m.name == 'Chauvet'));
    final withRanges = fixtures
        .expand((f) => f.modes)
        .expand((m) => m.channels)
        .where((c) => c.hasCapabilities);
    expect(withRanges, isNotEmpty);
    expect(withRanges.every((c) => c.capabilities.every((r) => r.label.isNotEmpty)), isTrue);
  });

  test('a picked mode becomes a profile that says where it came from', () async {
    final manufacturers = await asset.manufacturers();
    final fixtures = await asset.fixturesOf(manufacturers.firstWhere((m) => m.name == 'Chauvet'));
    final fixture = fixtures.firstWhere((f) => f.modes.length > 1);
    final profile = fixture.toProfile(fixture.modes.first);
    expect(profile.manufacturer, 'Chauvet');
    expect(profile.model, fixture.model);
    expect(profile.modeName, fixture.modes.first.name);
    expect(profile.sourceFormat, 'qlcplus');
    expect(profile.channelCount, fixture.modes.first.channelCount);
    // A multi-mode fixture gets the mode into the name, so two modes of the
    // same light are told apart in the template list.
    expect(profile.name, contains(fixture.modes.first.name));
  });

  test('moving heads keep their pan and tilt', () async {
    final manufacturers = await asset.manufacturers();
    final fixtures = await asset.fixturesOf(manufacturers.firstWhere((m) => m.name == 'Chauvet'));
    final movers = fixtures.where((f) => f.category == FixtureCategory.movingHead);
    expect(movers, isNotEmpty);
    final withPanTilt = movers.where(
      (f) => f.modes.first.channels.any((c) => c.function == ChannelFunction.pan) &&
          f.modes.first.channels.any((c) => c.function == ChannelFunction.tilt),
    );
    // Not every "moving head" in the library exposes both in its smallest
    // mode, but the overwhelming majority do — a mapping regression would
    // drop this to zero.
    expect(withPanTilt.length, greaterThan(movers.length ~/ 2));
  });
}
