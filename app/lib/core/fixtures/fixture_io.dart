import 'dart:convert';

import '../../models/channel_capability.dart';
import '../../models/channel_function.dart';
import '../../models/fixture_channel.dart';
import '../../models/fixture_profile.dart';
import 'qlcplus_format.dart';

/// Importing and exporting fixture profiles.
///
/// Three formats, chosen for what they're each good at:
///  * **JSON** — this app's own, lossless, and the one to use for moving a
///    fixture between two copies of the app.
///  * **`.qxf`** — QLC+ definitions. The widest reach: QLC+ itself ships
///    ~1700 of them and the Open Fixture Library exports to it, so this is
///    how a fixture that isn't in the bundled library gets in.
///  * **CSV** — a spreadsheet. Not pretty, but it's the format anyone can
///    edit without tooling, and the fastest way to type in a channel chart
///    off a manual.
///
/// GDTF is deliberately absent: reading it means unzipping an archive, and
/// the DMX-relevant parts of a `.gdtf` are better reached by exporting to
/// QLC+ first. Nothing here downloads anything — the app has to work at a
/// venue with no internet.

/// What came out of an import, plus anything the user should know about it.
class FixtureImportResult {
  final List<FixtureProfile> profiles;
  final List<String> warnings;

  const FixtureImportResult({required this.profiles, this.warnings = const []});
}

/// Reads [content] as whichever format [fileName]'s extension names.
///
/// Throws [FormatException] with a message worth showing when the file
/// can't be read as that format.
FixtureImportResult importFixtures(String fileName, String content) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.qxf') || lower.endsWith('.xml')) {
    final fixture = parseQxf(content);
    final profiles = fixture.toProfiles();
    return FixtureImportResult(
      profiles: profiles,
      warnings: [
        if (profiles.length > 1)
          '${fixture.model} has ${profiles.length} DMX modes — each became its own fixture, '
              'since a profile here is one fixed channel layout.',
      ],
    );
  }
  if (lower.endsWith('.csv')) return _importCsv(content);
  if (lower.endsWith('.json')) return _importJson(content);
  throw FormatException('Unsupported file type: $fileName');
}

/// This app's own format. Also accepts a project file, so a fixture list
/// can be lifted out of a whole show export.
FixtureImportResult _importJson(String content) {
  final Object? decoded;
  try {
    decoded = jsonDecode(content);
  } catch (e) {
    throw FormatException('Not valid JSON: $e');
  }

  List<dynamic>? entries;
  if (decoded is List) {
    entries = decoded;
  } else if (decoded is Map<String, dynamic>) {
    entries = (decoded['fixtures'] ?? decoded['fixtureProfiles']) as List?;
    // A single profile on its own.
    if (entries == null && decoded.containsKey('channels')) entries = [decoded];
  }
  if (entries == null || entries.isEmpty) {
    throw const FormatException('No fixtures found in this JSON file');
  }

  final profiles = <FixtureProfile>[];
  final warnings = <String>[];
  for (final entry in entries) {
    try {
      final map = Map<String, dynamic>.from(entry as Map);
      // Imported profiles are re-identified when added, so a file with no
      // id is perfectly fine.
      map.putIfAbsent('id', () => 'imported');
      profiles.add(FixtureProfile.fromJson(map));
    } catch (e) {
      warnings.add('Skipped one entry: $e');
    }
  }
  if (profiles.isEmpty) throw const FormatException('No readable fixtures in this JSON file');
  return FixtureImportResult(profiles: profiles, warnings: warnings);
}

const _csvHeader = 'fixture,channel,function,label,ranges';

/// Writes one row per channel, so a channel chart from a manual can be
/// typed straight into a spreadsheet.
///
/// The ranges column packs the value spans as
/// `0-3=Closed|4-7=Open|8-215=Strobe slow to fast`, which survives a round
/// trip and is still readable in a cell.
String exportFixturesCsv(List<FixtureProfile> profiles) {
  final buffer = StringBuffer()..writeln(_csvHeader);
  for (final profile in profiles) {
    for (final channel in profile.channels) {
      buffer.writeln([
        _csvField(profile.name),
        '${channel.offset + 1}',
        channel.function.name,
        _csvField(channel.customLabel ?? ''),
        _csvField(_packRanges(channel.capabilities)),
      ].join(','));
    }
  }
  return buffer.toString();
}

FixtureImportResult _importCsv(String content) {
  final lines = const LineSplitter().convert(content).where((l) => l.trim().isNotEmpty).toList();
  if (lines.isEmpty) throw const FormatException('The CSV file is empty');
  var start = 0;
  if (lines.first.toLowerCase().replaceAll(' ', '').startsWith('fixture,channel')) start = 1;

  final byFixture = <String, List<FixtureChannel>>{};
  final warnings = <String>[];
  for (var i = start; i < lines.length; i++) {
    final cells = _splitCsvLine(lines[i]);
    if (cells.length < 3) {
      warnings.add('Line ${i + 1}: expected at least fixture, channel and function');
      continue;
    }
    final name = cells[0].trim();
    if (name.isEmpty) continue;
    final function = ChannelFunction.values.firstWhere(
      (f) => f.name.toLowerCase() == cells[2].trim().toLowerCase(),
      orElse: () => ChannelFunction.generic,
    );
    final label = cells.length > 3 ? cells[3].trim() : '';
    final ranges = cells.length > 4 ? cells[4] : '';
    final channels = byFixture.putIfAbsent(name, () => []);
    channels.add(FixtureChannel(
      // Row order defines the channel order — the channel-number column is
      // for reading, not addressing, so a chart that starts at 1 or at 0
      // both import the same.
      offset: channels.length,
      function: function,
      customLabel: label.isEmpty ? null : label,
      capabilities: _unpackRanges(ranges),
    ));
  }
  if (byFixture.isEmpty) throw const FormatException('No readable fixtures in this CSV file');

  return FixtureImportResult(
    profiles: [
      for (final entry in byFixture.entries)
        FixtureProfile(
          id: 'imported',
          name: entry.key,
          category: _guessCategory(entry.value),
          channels: entry.value,
          sourceFormat: 'csv',
        ),
    ],
    warnings: warnings,
  );
}

/// This app's own lossless format.
String exportFixturesJson(List<FixtureProfile> profiles) {
  return const JsonEncoder.withIndent('  ').convert({
    'format': 'smartdmx.fixtures',
    'version': 1,
    'fixtures': [for (final profile in profiles) profile.toJson()],
  });
}

FixtureCategory _guessCategory(List<FixtureChannel> channels) {
  if (channels.any((c) => c.function.isPanTilt)) return FixtureCategory.movingHead;
  if (channels.any((c) => c.function.isColorMix)) return FixtureCategory.rgb;
  return FixtureCategory.generic;
}

String _packRanges(List<ChannelCapability> capabilities) {
  return [
    for (final capability in capabilities)
      '${capability.min}-${capability.max}=${capability.label.replaceAll('|', '/')}',
  ].join('|');
}

List<ChannelCapability> _unpackRanges(String packed) {
  final trimmed = packed.trim();
  if (trimmed.isEmpty) return const [];
  final capabilities = <ChannelCapability>[];
  for (final part in trimmed.split('|')) {
    final equals = part.indexOf('=');
    if (equals < 1) continue;
    final span = part.substring(0, equals).split('-');
    if (span.length != 2) continue;
    final min = int.tryParse(span[0].trim());
    final max = int.tryParse(span[1].trim());
    final label = part.substring(equals + 1).trim();
    if (min == null || max == null || label.isEmpty) continue;
    capabilities.add(ChannelCapability(
      min: min.clamp(0, 255),
      max: max.clamp(0, 255),
      label: label,
      kind: (max - min) >= qlcRangeWidthThreshold ? CapabilityKind.range : CapabilityKind.slot,
    ));
  }
  return normalizeCapabilities(capabilities);
}

String _csvField(String value) {
  if (!value.contains(',') && !value.contains('"') && !value.contains('\n')) return value;
  return '"${value.replaceAll('"', '""')}"';
}

/// A minimal RFC-4180 split: enough for quoted fields containing commas,
/// which is all a fixture chart ever needs.
List<String> _splitCsvLine(String line) {
  final cells = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (inQuotes) {
      if (char == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        buffer.write(char);
      }
    } else if (char == '"') {
      inQuotes = true;
    } else if (char == ',') {
      cells.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  cells.add(buffer.toString());
  return cells;
}
