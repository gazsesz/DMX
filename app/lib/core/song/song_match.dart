import '../../models/song_show.dart';

/// Lower case, accents and punctuation dropped, spaces squeezed — so
/// "Daft Punk – One More Time (Radio Edit).mp3" and "one more time radio
/// edit" compare equal on the words.
String normalizeTrackText(String text) {
  const accents = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ő': 'o', 'ø': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ű': 'u',
    'ñ': 'n', 'ç': 'c', 'ß': 'ss',
  };
  final buffer = StringBuffer();
  for (final rune in text.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    final plain = accents[ch] ?? ch;
    final isWordChar = RegExp(r'[a-z0-9]').hasMatch(plain);
    buffer.write(isWordChar ? plain : ' ');
  }
  return buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// The song file's name without its extension.
String _fileStem(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot > 0 ? fileName.substring(0, dot) : fileName;
}

/// Whether [haystack] holds [needle] as whole words.
bool _containsWords(String haystack, String needle) =>
    needle.isNotEmpty && ' $haystack '.contains(' $needle ');

/// The show to follow when [title] by [artist] is on the master deck, or
/// null. A show paired to the track (its [SongShow.trackTitle]) wins; after
/// that a show named after the track, then one whose song file is named
/// after it. Shows without cues are skipped — there would be nothing to play.
SongShow? matchSongShow(Iterable<SongShow> shows, {required String title, String artist = ''}) {
  final t = normalizeTrackText(title);
  if (t.isEmpty) return null;
  final a = normalizeTrackText(artist);
  final playable = shows.where((s) => s.cues.isNotEmpty).toList();

  for (final show in playable) {
    if (show.trackTitle.isEmpty) continue;
    if (normalizeTrackText(show.trackTitle) != t) continue;
    final showArtist = normalizeTrackText(show.trackArtist);
    if (showArtist.isEmpty || a.isEmpty || showArtist == a) return show;
  }

  final named = {t, if (a.isNotEmpty) '$a $t', if (a.isNotEmpty) '$t $a'};
  for (final show in playable) {
    if (show.trackTitle.isNotEmpty) continue;
    if (named.contains(normalizeTrackText(show.name))) return show;
  }

  for (final show in playable) {
    if (show.trackTitle.isNotEmpty) continue;
    final file = show.audio?.fileName;
    if (file == null) continue;
    final stem = normalizeTrackText(_fileStem(file));
    if (stem == t || named.contains(stem)) return show;
    if (_containsWords(stem, t) && (a.isEmpty || _containsWords(stem, a))) return show;
  }
  return null;
}
