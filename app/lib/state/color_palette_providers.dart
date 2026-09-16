import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const prefCustomColors = 'colors.custom';

/// Colours mixed by hand in the scene editor's palette and kept.
///
/// App-level rather than part of the project file: a house colour is a
/// property of the rig and the room, not of one show, and you want it there
/// the moment you start the next project. Stored as `rrggbb` strings, which
/// survives a shared-preferences round trip unchanged.
class CustomColorsNotifier extends StateNotifier<List<List<int>>> {
  CustomColorsNotifier([super.initial = const []]) {
    _load();
  }

  /// Loaded after the first frame on purpose — unlike the connection
  /// settings, nothing is built from these up front, so a swatch row that
  /// fills in a frame later costs nothing.
  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final stored = customColorsFromStrings(sp.getStringList(prefCustomColors));
    if (stored.isNotEmpty) state = stored;
  }

  /// Adds [rgb] unless that exact colour is already saved — tapping Save
  /// twice on the same mix shouldn't grow the row.
  void add(List<int> rgb) {
    final colour = [rgb[0].clamp(0, 255), rgb[1].clamp(0, 255), rgb[2].clamp(0, 255)];
    if (state.any((c) => _same(c, colour))) return;
    state = [...state, colour];
    _persist();
  }

  void remove(List<int> rgb) {
    state = [for (final c in state) if (!_same(c, rgb)) c];
    _persist();
  }

  static bool _same(List<int> a, List<int> b) => a[0] == b[0] && a[1] == b[1] && a[2] == b[2];

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(prefCustomColors, [for (final c in state) hexOf(c)]);
  }
}

final customColorsProvider = StateNotifierProvider<CustomColorsNotifier, List<List<int>>>(
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
