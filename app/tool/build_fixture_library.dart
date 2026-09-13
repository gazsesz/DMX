// Preprocesses the QLC+ fixture definitions into the assets the app ships.
//
// Run it against a checkout of https://github.com/mcallegari/qlcplus:
//
//   dart run tool/build_fixture_library.dart <path-to-qlcplus>/resources/fixtures
//
// It writes assets/fixtures/index.json.gz (the manufacturer list, read when
// the browser opens) and assets/fixtures/m/<slug>.json.gz (one file per
// manufacturer, read only when that manufacturer is opened). Splitting it up
// matters: the whole library is ~19 MB of XML, and a phone shouldn't have to
// decompress and parse all of it to show a list of brand names.
//
// Parsing goes through the same core/fixtures/qlcplus_format.dart the
// runtime importer uses, so a fixture from the bundled library and the same
// fixture imported from a .qxf file come out identical.
//
// The QLC+ fixture definitions are Apache-2.0; assets/fixtures/LICENSE.txt
// carries the licence text the attribution requires.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dmx_controller/core/fixtures/qlcplus_format.dart';
import 'package:dmx_controller/models/fixture_profile.dart';

String _slug(String name) {
  final cleaned = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  return cleaned.replaceAll(RegExp(r'^-+|-+$'), '');
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/build_fixture_library.dart <qlcplus>/resources/fixtures');
    exit(64);
  }
  final source = Directory(args.first);
  if (!source.existsSync()) {
    stderr.writeln('No such directory: ${source.path}');
    exit(66);
  }

  final outDir = Directory('assets/fixtures');
  final perManufacturer = Directory('assets/fixtures/m');
  // Keep the licence across a rebuild — it's checked in next to the data.
  final licence = File('${outDir.path}/LICENSE.txt');
  final licenceText = licence.existsSync() ? licence.readAsStringSync() : null;
  if (outDir.existsSync()) outDir.deleteSync(recursive: true);
  perManufacturer.createSync(recursive: true);
  if (licenceText != null) licence.writeAsStringSync(licenceText);

  final byManufacturer = <String, List<Map<String, Object>>>{};
  var fixtureCount = 0;
  var modeCount = 0;
  var skipped = 0;

  final files = source
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.qxf'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    try {
      final fixture = parseQxf(file.readAsStringSync());
      if (fixture.manufacturer.isEmpty) {
        skipped++;
        continue;
      }

      final modes = <Map<String, Object>>[];
      for (final mode in fixture.modes) {
        modes.add({
          'n': mode.name,
          'ch': [
            for (final channel in mode.channels)
              {
                'f': channel.function.name,
                'l': channel.name,
                if (channel.capabilities.isNotEmpty)
                  'c': [
                    for (final capability in channel.capabilities)
                      {
                        'min': capability.min,
                        'max': capability.max,
                        'label': capability.label,
                        'kind': capability.kind.name,
                      },
                  ],
              },
          ],
        });
        modeCount++;
      }

      byManufacturer.putIfAbsent(fixture.manufacturer, () => []).add({
        'n': fixture.model,
        't': fixture.type,
        'cat': fixture.category.name,
        'm': modes,
      });
      fixtureCount++;
    } catch (e) {
      stderr.writeln('Skipped ${file.path}: $e');
      skipped++;
    }
  }

  final indexEntries = <Map<String, Object>>[];
  final names = byManufacturer.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  var totalBytes = 0;
  for (final manufacturer in names) {
    final fixtures = byManufacturer[manufacturer]!
      ..sort((a, b) => (a['n']! as String).toLowerCase().compareTo((b['n']! as String).toLowerCase()));
    final slug = _slug(manufacturer);
    final payload = gzip.encode(utf8.encode(jsonEncode({'n': manufacturer, 'f': fixtures})));
    File('${perManufacturer.path}/$slug.json.gz').writeAsBytesSync(payload);
    totalBytes += payload.length;
    indexEntries.add({
      'n': manufacturer,
      's': slug,
      'c': fixtures.length,
      // Every category present, so the browser can filter brands by type
      // without opening each file.
      'cats': {for (final f in fixtures) f['cat']! as String}.toList()..sort(),
    });
  }

  final index = gzip.encode(utf8.encode(jsonEncode({
    'version': 1,
    'source': 'QLC+ fixture definitions (Apache-2.0)',
    'fixtures': fixtureCount,
    'modes': modeCount,
    'manufacturers': indexEntries,
  })));
  File('${outDir.path}/index.json.gz').writeAsBytesSync(index);
  totalBytes += index.length;

  // Sanity check: a category mapping regression would quietly turn every
  // moving head into a generic fixture, and nothing else would complain.
  final categories = <String, int>{};
  for (final fixtures in byManufacturer.values) {
    for (final fixture in fixtures) {
      categories.update(fixture['cat']! as String, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  assert(FixtureCategory.values.length == 3);

  stdout.writeln('Wrote $fixtureCount fixtures / $modeCount modes '
      'from ${names.length} manufacturers ($skipped skipped)');
  stdout.writeln('Categories: $categories');
  stdout.writeln('Assets total ${(totalBytes / 1024 / 1024).toStringAsFixed(2)} MB compressed');
}
