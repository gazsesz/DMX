import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const prefCustomColors = 'colors.custom';
const _prefCustomColorsV2 = 'colors.custom.v2';

/// A colour mixed by hand and kept, with an optional name — "Deep Blue"
/// reads a lot better on a chip than "#1e3a8a" once you have a handful of
/// them saved.
class SavedColor {
  final String? name;
  final List<int> rgb;

  const SavedColor({this.name, required this.rgb});

  /// The hex code until it's actually given a name.
  String get displayName {
    final trimmed = name?.trim();
    return trimmed != null && trimmed.isNotEmpty ? trimmed : '#${hexOf(rgb)}';
  }

  SavedColor copyWith({String? name}) => SavedColor(name: name, rgb: rgb);

  Map<String, dynamic> toJson() => {'name': name, 'rgb': rgb};

  factory SavedColor.fromJson(Map<String, dynamic> json) => SavedColor(
    name: json['name'] as String?,
    rgb: (json['rgb'] as List).map((v) => (v as num).toInt()).toList(),
  );
}

/// Colours mixed by hand in the scene editor's palette and kept.
///
/// App-level rather than part of the project file: a house colour is a
/// property of the rig and the room, not of one show, and you want it there
/// the moment you start the next project. Stored as JSON (name + `rrggbb`),
/// which survives a shared-preferences round trip unchanged.
class CustomColorsNotifier extends StateNotifier<List<SavedColor>> {
  CustomColorsNotifier([super.initial = const []]) {
    _load();
  }

  /// Loaded after the first frame on purpose — unlike the connection
  /// settings, nothing is built from these up front, so a swatch row that
  /// fills in a frame later costs nothing.
  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final storedV2 = sp.getStringList(_prefCustomColorsV2);
    if (storedV2 != null) {
      state = [
        for (final entry in storedV2) ?_decodeSavedColor(entry),
      ];
      return;
    }
    // First run after the named-colours upgrade: bring the old unnamed hex
    // list across once, then write it back out in the new format.
    final legacy = customColorsFromStrings(sp.getStringList(prefCustomColors));
    if (legacy.isNotEmpty) {
      state = [for (final rgb in legacy) SavedColor(rgb: rgb)];
      await _persist();
    }
  }

  static SavedColor? _decodeSavedColor(String entry) {
    try {
      return SavedColor.fromJson(jsonDecode(entry) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Adds [rgb] unless that exact colour is already saved — tapping Save
  /// twice on the same mix shouldn't grow the row.
  void add(List<int> rgb, {String? name}) {
    final colour = [rgb[0].clamp(0, 255), rgb[1].clamp(0, 255), rgb[2].clamp(0, 255)];
    if (state.any((c) => _same(c.rgb, colour))) return;
    state = [...state, SavedColor(name: name, rgb: colour)];
    _persist();
  }

  void rename(List<int> rgb, String name) {
    final trimmed = name.trim();
    state = [
      for (final c in state)
        if (_same(c.rgb, rgb)) c.copyWith(name: trimmed.isEmpty ? null : trimmed) else c,
    ];
    _persist();
  }

  void remove(List<int> rgb) {
    state = [for (final c in state) if (!_same(c.rgb, rgb)) c];
    _persist();
  }

  static bool _same(List<int> a, List<int> b) => a[0] == b[0] && a[1] == b[1] && a[2] == b[2];

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_prefCustomColorsV2, [for (final c in state) jsonEncode(c.toJson())]);
  }
}

final customColorsProvider = StateNotifierProvider<CustomColorsNotifier, List<SavedColor>>(
  (ref) => CustomColorsNotifier(),
);

String hexOf(List<int> rgb) =>
    rgb.map((v) => v.clamp(0, 255).toRadixString(16).padLeft(2, '0')).join();

List<List<int>> customColorsFromStrings(List<String>? stored) {
  if (stored == null) return const [];
  final result = <List<int>>[];
  for (final entry in stored) {
    final hex = entry.trim().replaceFirst('#', '');
    if (hex.length != 6) continue;
    final value = int.tryParse(hex, radix: 16);
    if (value == null) continue;
    result.add([(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF]);
  }
  return result;
}
