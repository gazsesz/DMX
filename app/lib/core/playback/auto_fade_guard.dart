/// Decides whether the app-wide Auto-Fade switch should be forced off while
/// a Beat Flash bank is the thing actually playing, and handed back once
/// playback moves on to something else.
///
/// Auto-fade smears a step's cross-fade into a slow ramp tied to the tempo —
/// exactly wrong for a flash, which wants a hard cut. Rather than have every
/// caller reason about "was it on before, did I turn it off, should I turn
/// it back on", this holds that one bit of state and hands back a plain
/// instruction each time the active target changes.
class AutoFadeGuard {
  bool _suppressed = false;

  /// True while this guard has forced auto-fade off and hasn't put it back
  /// yet.
  bool get isSuppressed => _suppressed;

  /// Call whenever the thing actually playing changes (a new zone, a new
  /// program, or playback stopping). [isFlashBank] says whether the new
  /// target is a Beat Flash bank; [autoFadeCurrentlyOn] is the switch's live
  /// state.
  ///
  /// Returns `false` if the caller should now turn auto-fade off, `true` if
  /// it should turn it back on, or `null` if nothing needs to change.
  bool? onTargetChanged({required bool isFlashBank, required bool autoFadeCurrentlyOn}) {
    if (isFlashBank) {
      if (!_suppressed && autoFadeCurrentlyOn) {
        _suppressed = true;
        return false;
      }
      return null;
    }
    if (_suppressed) {
      _suppressed = false;
      return true;
    }
    return null;
  }

  /// Call when playback stops outright — if auto-fade is still suppressed,
  /// tells the caller to restore it, same as leaving a flash bank's zone.
  bool? onStopped() {
    if (!_suppressed) return null;
    _suppressed = false;
    return true;
  }
}
