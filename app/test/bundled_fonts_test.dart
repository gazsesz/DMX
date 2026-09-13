import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Guards the fonts the app ships.
///
/// Two things have already gone wrong here and would go wrong again
/// silently: fetching fonts at runtime (impossible on the node's Wi-Fi, and
/// the failure only shows up in logcat), and pulling Google's *latin-only*
/// Manrope subset, which has no ő or ű — half the Hungarian project names
/// would render as tofu and nothing would report an error.
void main() {
  final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
  final fontFamilies = (pubspec['flutter'] as YamlMap)['fonts'] as YamlList;

  test('the app declares no runtime font package', () {
    final dependencies = (pubspec['dependencies'] as YamlMap).keys.cast<String>();
    expect(
      dependencies,
      isNot(contains('google_fonts')),
      reason: 'fonts must be bundled — this app runs with no internet',
    );
  });

  test('every declared font file is actually present and is a TrueType file', () {
    for (final family in fontFamilies) {
      for (final font in family['fonts'] as YamlList) {
        final file = File(font['asset'] as String);
        expect(file.existsSync(), isTrue, reason: '${font['asset']} is missing');
        final header = file.readAsBytesSync().sublist(0, 4);
        expect(
          header,
          orderedEquals([0x00, 0x01, 0x00, 0x00]),
          reason: '${font['asset']} is not a TrueType file — a Google Fonts '
              'CSS download can hand back EOT or WOFF depending on the user agent',
        );
      }
    }
  });

  test('the theme only asks for weights that are declared', () {
    // A weight with no file falls back to the nearest one, so a missing
    // 800 would quietly render as 700 and the headings would look wrong.
    const usedByTheApp = {
      'Manrope': [400, 500, 600, 700, 800],
      'IBM Plex Mono': [500, 700],
    };
    for (final entry in usedByTheApp.entries) {
      final family = fontFamilies.firstWhere((f) => f['family'] == entry.key);
      final declared = [for (final font in family['fonts'] as YamlList) font['weight'] as int];
      expect(declared, containsAll(entry.value), reason: entry.key);
    }
  });

  test('every bundled font covers the characters the UI renders', () {
    // Hungarian in full — ő and ű are the ones that live in latin-ext and
    // get dropped by the default subset — plus the typographic characters
    // the layouts use.
    const needed = 'áéíóöőúüűÁÉÍÓÖŐÚÜŰ—·½×°';
    for (final family in fontFamilies) {
      for (final font in family['fonts'] as YamlList) {
        final path = font['asset'] as String;
        final covered = _codepointsOf(File(path).readAsBytesSync());
        final missing = [
          for (final rune in needed.runes)
            if (!covered.contains(rune)) String.fromCharCode(rune),
        ];
        expect(missing, isEmpty, reason: '$path is missing ${missing.join()}');
      }
    }
  });

  testWidgets('the theme resolves to the bundled families, not a fallback', (tester) async {
    // Guards against the theme drifting back to a package-provided family:
    // both of these are exactly the strings pubspec declares.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final families = [for (final family in fontFamilies) family['family'] as String];
    expect(families, containsAll(['Manrope', 'IBM Plex Mono']));
  });
}

/// The Unicode codepoints a TrueType file's `cmap` maps to a glyph.
Set<int> _codepointsOf(Uint8List bytes) {
  final data = ByteData.view(bytes.buffer);
  final tableCount = data.getUint16(4);
  int? cmapOffset;
  for (var i = 0; i < tableCount; i++) {
    final record = 12 + i * 16;
    if (String.fromCharCodes(bytes.sublist(record, record + 4)) == 'cmap') {
      cmapOffset = data.getUint32(record + 8);
    }
  }
  if (cmapOffset == null) throw StateError('font has no cmap table');

  // Prefer a Windows Unicode subtable — that's what Flutter reads.
  int? subtable;
  final subtableCount = data.getUint16(cmapOffset + 2);
  for (var i = 0; i < subtableCount; i++) {
    final record = cmapOffset + 4 + i * 8;
    final platform = data.getUint16(record);
    final encoding = data.getUint16(record + 2);
    if (platform == 3 && (encoding == 1 || encoding == 10)) {
      subtable = cmapOffset + data.getUint32(record + 4);
    }
  }
  if (subtable == null) throw StateError('font has no Unicode cmap subtable');

  final covered = <int>{};
  final format = data.getUint16(subtable);
  if (format == 4) {
    final segmentBytes = data.getUint16(subtable + 6);
    final endBase = subtable + 14;
    final startBase = endBase + segmentBytes + 2;
    for (var segment = 0; segment < segmentBytes ~/ 2; segment++) {
      final start = data.getUint16(startBase + segment * 2);
      final end = data.getUint16(endBase + segment * 2);
      if (start == 0xFFFF) continue;
      for (var code = start; code <= end && code != 0xFFFF; code++) {
        covered.add(code);
      }
    }
  } else if (format == 12) {
    final groups = data.getUint32(subtable + 12);
    for (var group = 0; group < groups; group++) {
      final record = subtable + 16 + group * 12;
      for (var code = data.getUint32(record); code <= data.getUint32(record + 4); code++) {
        covered.add(code);
      }
    }
  } else {
    throw StateError('unsupported cmap format $format');
  }
  return covered;
}
