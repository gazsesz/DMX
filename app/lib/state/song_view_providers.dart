import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

/// How a song show's timeline was last looked at: its zoom and how far it was
/// scrolled. A view setting of this device, so it lives in the app's
/// preferences, not in the project (and never in an export).
class SongView {
  final double pixelsPerBeat;
  final double scrollOffset;

  const SongView({required this.pixelsPerBeat, required this.scrollOffset});

  String encode() => '$pixelsPerBeat;$scrollOffset';

  static SongView? decode(String? text) {
    if (text == null) return null;
    final parts = text.split(';');
    if (parts.length != 2) return null;
    final ppb = double.tryParse(parts[0]);
    final offset = double.tryParse(parts[1]);
    if (ppb == null || offset == null || ppb <= 0 || offset < 0) return null;
    return SongView(pixelsPerBeat: ppb, scrollOffset: offset);
  }
}

String songViewPrefKey(String showId) => 'songView.$showId';

/// The views remembered this session, by show id — what the editor reads
/// synchronously when it opens, so it comes up already at the old zoom.
///
/// A plain cache rather than a Riverpod provider on purpose: the editor writes
/// it from `dispose`, where changing a provider is not allowed, and nothing
/// watches it.
final _sessionViews = <String, SongView>{};

SongView? rememberedSongView(String showId) => _sessionViews[showId];

/// Remembers [view] for this session and writes it to the preferences.
void rememberSongView(String showId, SongView view) {
  _sessionViews[showId] = view;
  saveSongView(showId, view);
}

/// Forgets the session's views (for tests).
@visibleForTesting
void resetSongViewCache() => _sessionViews.clear();

/// Writes [view] to the preferences. Failures are swallowed: losing a zoom
/// level is not worth an error.
Future<void> saveSongView(String showId, SongView view) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(songViewPrefKey(showId), view.encode());
  } catch (_) {}
}

/// The view saved for [showId] in an earlier session, if any.
Future<SongView?> loadSongView(String showId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return SongView.decode(prefs.getString(songViewPrefKey(showId)));
  } catch (_) {
    return null;
  }
}
