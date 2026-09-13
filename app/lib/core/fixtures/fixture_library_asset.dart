import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../models/channel_capability.dart';
import '../../models/channel_function.dart';
import '../../models/fixture_channel.dart';
import '../../models/fixture_profile.dart';

/// One manufacturer in the bundled library's index.
class LibraryManufacturer {
  final String name;
  final String slug;
  final int fixtureCount;
  final List<String> categories;

  const LibraryManufacturer({
    required this.name,
    required this.slug,
    required this.fixtureCount,
    required this.categories,
  });
}

/// One DMX mode of a library fixture — this is what actually becomes a
/// [FixtureProfile] when the user picks it.
class LibraryMode {
  final String name;
  final List<FixtureChannel> channels;

  const LibraryMode({required this.name, required this.channels});

  int get channelCount => channels.length;
}

/// One fixture in the library, with all of its modes.
class LibraryFixture {
  final String manufacturer;
  final String model;
  final String type;
  final FixtureCategory category;
  final List<LibraryMode> modes;

  const LibraryFixture({
    required this.manufacturer,
    required this.model,
    required this.type,
    required this.category,
    required this.modes,
  });

  /// Turns one mode into a profile ready to add to the project's library.
  /// The id is a placeholder — the notifier assigns a real one.
  FixtureProfile toProfile(LibraryMode mode) => FixtureProfile(
    id: 'library',
    name: modes.length == 1 ? model : '$model ${mode.name}',
    category: category,
    channels: mode.channels,
    manufacturer: manufacturer,
    model: model,
    modeName: mode.name,
    sourceFormat: 'qlcplus',
  );
}

/// Reads the fixture library that ships with the app.
///
/// The whole library is ~19 MB of source XML, which is why it's baked into
/// compressed per-manufacturer JSON at build time (see
/// tool/build_fixture_library.dart) and read one manufacturer at a time:
/// showing a list of brand names must not cost a phone a second of parsing,
/// and this all has to work with no internet at a venue.
class FixtureLibraryAsset {
  static const _indexPath = 'assets/fixtures/index.json.gz';

  List<LibraryManufacturer>? _index;
  int _fixtureCount = 0;
  int _modeCount = 0;
  final Map<String, List<LibraryFixture>> _cache = {};

  int get fixtureCount => _fixtureCount;
  int get modeCount => _modeCount;

  Future<List<LibraryManufacturer>> manufacturers() async {
    final cached = _index;
    if (cached != null) return cached;
    final json = await _readGzipJson(_indexPath);
    _fixtureCount = json['fixtures'] as int? ?? 0;
    _modeCount = json['modes'] as int? ?? 0;
    final list = [
      for (final entry in (json['manufacturers'] as List? ?? const []))
        LibraryManufacturer(
          name: (entry as Map)['n'] as String,
          slug: entry['s'] as String,
          fixtureCount: entry['c'] as int? ?? 0,
          categories: [for (final c in (entry['cats'] as List? ?? const [])) c as String],
        ),
    ];
    _index = list;
    return list;
  }

  /// Every fixture of one manufacturer. Cached, since the browser goes in
  /// and out of the same brand while someone compares modes.
  Future<List<LibraryFixture>> fixturesOf(LibraryManufacturer manufacturer) async {
    final cached = _cache[manufacturer.slug];
    if (cached != null) return cached;
    final json = await _readGzipJson('assets/fixtures/m/${manufacturer.slug}.json.gz');
    final name = json['n'] as String? ?? manufacturer.name;
    final fixtures = [
      for (final entry in (json['f'] as List? ?? const []))
        _decodeFixture(name, entry as Map<String, dynamic>),
    ];
    _cache[manufacturer.slug] = fixtures;
    return fixtures;
  }

  static LibraryFixture _decodeFixture(String manufacturer, Map<String, dynamic> json) {
    return LibraryFixture(
      manufacturer: manufacturer,
      model: json['n'] as String? ?? '',
      type: json['t'] as String? ?? 'Other',
      category: FixtureCategory.values.firstWhere(
        (c) => c.name == json['cat'],
        orElse: () => FixtureCategory.generic,
      ),
      modes: [
        for (final mode in (json['m'] as List? ?? const []))
          LibraryMode(
            name: (mode as Map)['n'] as String? ?? '',
            channels: _decodeChannels(mode['ch'] as List? ?? const []),
          ),
      ],
    );
  }

  static List<FixtureChannel> _decodeChannels(List raw) {
    final channels = <FixtureChannel>[];
    for (var i = 0; i < raw.length; i++) {
      final entry = raw[i] as Map;
      final function = ChannelFunction.values.firstWhere(
        (f) => f.name == entry['f'],
        orElse: () => ChannelFunction.generic,
      );
      final sourceLabel = (entry['l'] as String?)?.trim();
      channels.add(FixtureChannel(
        offset: i,
        function: function,
        // Keep the manufacturer's channel name unless it just repeats the
        // generic label, so a fader reads "Colour Macro" not "Color Wheel".
        customLabel: sourceLabel == null || sourceLabel.isEmpty || sourceLabel == function.label
            ? null
            : sourceLabel,
        capabilities: normalizeCapabilities([
          for (final c in (entry['c'] as List? ?? const []))
            ChannelCapability(
              min: (c as Map)['min'] as int,
              max: c['max'] as int,
              label: c['label'] as String,
              kind: CapabilityKind.values.firstWhere(
                (k) => k.name == c['kind'],
                orElse: () => CapabilityKind.slot,
              ),
            ),
        ]),
      ));
    }
    return channels;
  }

  static Future<Map<String, dynamic>> _readGzipJson(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    return jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
  }
}
