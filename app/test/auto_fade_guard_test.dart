import 'package:dmx_controller/core/playback/auto_fade_guard.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Smart Program should suspend the app-wide Auto-Fade switch for exactly
/// as long as a Beat Flash bank is the zone actually playing, and hand it
/// straight back the moment playback moves to anything else — never
/// touching it at all if it wasn't on to begin with.
void main() {
  test('turns auto-fade off the first time a flash bank becomes the target', () {
    final guard = AutoFadeGuard();
    expect(
      guard.onTargetChanged(isFlashBank: true, autoFadeCurrentlyOn: true),
      isFalse,
      reason: 'false means "turn it off"',
    );
    expect(guard.isSuppressed, isTrue);
  });

  test('does nothing on a flash bank if auto-fade was already off', () {
    final guard = AutoFadeGuard();
    expect(guard.onTargetChanged(isFlashBank: true, autoFadeCurrentlyOn: false), isNull);
    expect(guard.isSuppressed, isFalse);
  });

  test('does not re-suppress on a second flash bank in a row', () {
    final guard = AutoFadeGuard();
    guard.onTargetChanged(isFlashBank: true, autoFadeCurrentlyOn: true);
    // Zone re-fires (e.g. updateProgram) while still on a flash bank —
    // auto-fade is already off, so there's nothing new to do.
    expect(guard.onTargetChanged(isFlashBank: true, autoFadeCurrentlyOn: false), isNull);
    expect(guard.isSuppressed, isTrue);
  });

  test('restores auto-fade once the target is no longer a flash bank', () {
    final guard = AutoFadeGuard();
    guard.onTargetChanged(isFlashBank: true, autoFadeCurrentlyOn: true);
    expect(
      guard.onTargetChanged(isFlashBank: false, autoFadeCurrentlyOn: false),
      isTrue,
      reason: 'true means "turn it back on"',
    );
    expect(guard.isSuppressed, isFalse);
  });

  test('never touches auto-fade for non-flash targets', () {
    final guard = AutoFadeGuard();
    expect(guard.onTargetChanged(isFlashBank: false, autoFadeCurrentlyOn: true), isNull);
    expect(guard.onTargetChanged(isFlashBank: false, autoFadeCurrentlyOn: false), isNull);
  });

  test('stopping while suppressed hands auto-fade back', () {
    final guard = AutoFadeGuard();
    guard.onTargetChanged(isFlashBank: true, autoFadeCurrentlyOn: true);
    expect(guard.onStopped(), isTrue);
    expect(guard.isSuppressed, isFalse);
  });

  test('stopping while not suppressed does nothing', () {
    final guard = AutoFadeGuard();
    expect(guard.onStopped(), isNull);
  });
}
