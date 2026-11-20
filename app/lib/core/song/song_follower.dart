import '../../models/song_show.dart';
import '../audio/osc_beat_source.dart';
import 'song_match.dart';

/// What Song watch is doing, for the UI.
enum SongWatchPhase {
  /// Switched off.
  off,

  /// Waiting for a track that has a show.
  watching,

  /// A show is following the master deck.
  following,
}

class SongWatchStatus {
  final SongWatchPhase phase;

  /// The master deck's track, as rkbx_link names it.
  final String? title;
  final String? artist;

  /// The show for that track, if there is one.
  final String? showName;

  const SongWatchStatus({this.phase = SongWatchPhase.off, this.title, this.artist, this.showName});

  @override
  bool operator ==(Object other) =>
      other is SongWatchStatus &&
      other.phase == phase &&
      other.title == title &&
      other.artist == artist &&
      other.showName == showName;

  @override
  int get hashCode => Object.hash(phase, title, artist, showName);
}

/// What the follower asks the app to do.
abstract class SongFollowerActions {
  /// The shows to match a track against.
  List<SongShow> get shows;

  /// Remembers what is running now (only if nothing is remembered yet) and
  /// stops it, then starts [show] at [from] on the deck's clock. Returns
  /// false when the show couldn't start.
  Future<bool> takeOver(SongShow show, Duration from);

  /// Feeds the deck's position to the running show's clock.
  void report(Duration position, double rate);

  /// The id of the show the app is playing now, if any — when it isn't the
  /// one the follower started, someone took the stage by hand.
  String? get playingShowId;

  /// Stops the show and brings back what was running before it.
  Future<void> giveBack();

  /// Stops the show but keeps what was running before remembered — another
  /// track's show is about to take over.
  void stopShow();

  /// Forgets what was running before without starting it again — the
  /// performer started something else themselves.
  void forget();
}

/// Song watch's brain: watches rkbx_link's master deck and, when a track with
/// a song show plays, hands the stage to that show for as long as the track
/// plays, then gives it back to whatever was running before.
///
/// Pure logic over [RkbxDeckState] updates and a clock, so it is testable
/// without a network or the layer players.
class SongFollower {
  /// A deck whose position hasn't moved for this long has stopped (paused,
  /// or rkbx_link went quiet): the show ends and the old program returns.
  static const stopAfter = Duration(milliseconds: 2500);

  /// The position has to have moved forward on two reports at least this far
  /// apart before a show takes over, so loading a track or scrubbing through
  /// it in the browser doesn't fire the lights.
  static const startAfterMoving = Duration(milliseconds: 400);

  SongFollower(this.actions);

  final SongFollowerActions actions;

  SongWatchStatus _status = const SongWatchStatus(phase: SongWatchPhase.watching);
  SongWatchStatus get status => _status;

  String _trackKey = '';
  SongShow? _match;
  String? _followingId;

  /// The track whose show already ran (or was cut short by hand): it isn't
  /// started again until another track has played.
  String? _doneTrackKey;

  double? _lastTime;
  DateTime? _lastAdvanceAt;
  DateTime? _movingSince;
  bool _busy = false;

  bool get isFollowing => _followingId != null;

  /// Feeds one update from rkbx_link, received at [now].
  Future<void> onDeck(RkbxDeckState deck, DateTime now) async {
    if (_busy) return;
    _busy = true;
    try {
      await _onDeck(deck, now);
    } finally {
      _busy = false;
    }
  }

  Future<void> _onDeck(RkbxDeckState deck, DateTime now) async {
    final title = deck.title ?? '';
    final artist = deck.artist ?? '';
    final key = '${normalizeTrackText(title)}|${normalizeTrackText(artist)}';
    if (key != _trackKey) {
      _trackKey = key;
      _match = matchSongShow(actions.shows, title: title, artist: artist);
      _movingSince = null;
      _lastTime = null;
      if (_doneTrackKey != key) _doneTrackKey = null;
      if (isFollowing && _match?.id != _followingId) {
        // The DJ moved on to another track: its own show takes over straight
        // away, or the old program comes back.
        await _end(giveBack: _match == null);
      }
    }

    // Has the deck moved on?
    final time = deck.timeSec;
    if (time != null) {
      final last = _lastTime;
      if (last != null && time > last) {
        _lastAdvanceAt = now;
        _movingSince ??= now;
      } else if (last != null && time < last - 1) {
        // A jump back (loop, cue, restart) is still a playing deck.
        _lastAdvanceAt = now;
      }
      _lastTime = time;
    }

    if (isFollowing && actions.playingShowId != _followingId) {
      // Stopped or replaced by hand: leave the stage to the performer.
      _followingId = null;
      _doneTrackKey = key;
      actions.forget();
    }

    final match = _match;
    if (isFollowing) {
      if (time != null) actions.report(Duration(microseconds: (time * 1e6).round()), deck.rate);
    } else if (match != null &&
        time != null &&
        _doneTrackKey != key &&
        _movingSince != null &&
        now.difference(_movingSince!) >= startAfterMoving &&
        _isMoving(now)) {
      final from = Duration(microseconds: (time * 1e6).round());
      if (await actions.takeOver(match, from)) {
        _followingId = match.id;
        actions.report(from, deck.rate);
      } else {
        _doneTrackKey = key;
      }
    }
    _setStatus(deck);
  }

  /// Checks for a stopped deck; call every few hundred milliseconds.
  Future<void> onTick(DateTime now) async {
    if (!isFollowing || _busy) return;
    if (actions.playingShowId != _followingId) {
      // The show reached its end, or was stopped by hand.
      _followingId = null;
      _doneTrackKey = _trackKey;
      if (actions.playingShowId == null) {
        await actions.giveBack();
      } else {
        actions.forget();
      }
      _setStatus(null);
      return;
    }
    if (!_isMoving(now)) {
      _busy = true;
      try {
        // A paused deck: the same track playing on starts the show again.
        await _end(giveBack: true);
        _movingSince = null;
      } finally {
        _busy = false;
      }
      _setStatus(null);
    }
  }

  /// Ends the show without waiting for the deck — Song watch switched off.
  Future<void> stop() async {
    if (isFollowing) await _end(giveBack: true);
    _status = const SongWatchStatus(phase: SongWatchPhase.off);
  }

  bool _isMoving(DateTime now) => _lastAdvanceAt != null && now.difference(_lastAdvanceAt!) < stopAfter;

  Future<void> _end({required bool giveBack}) async {
    _followingId = null;
    if (giveBack) {
      await actions.giveBack();
    } else {
      actions.stopShow();
    }
  }

  void _setStatus(RkbxDeckState? deck) {
    _status = SongWatchStatus(
      phase: isFollowing ? SongWatchPhase.following : SongWatchPhase.watching,
      title: deck?.title ?? _status.title,
      artist: deck?.artist ?? _status.artist,
      showName: _match?.name,
    );
  }
}
