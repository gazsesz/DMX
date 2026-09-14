import 'package:dmx_controller/models/smart_program.dart';
import 'package:dmx_controller/state/playback_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The dock's Start button resumes whatever played last, so that memory has
/// to survive the stop that made the button appear in the first place.
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    // The app does this at startup for the same reason: a provider only
    // starts listening once it exists, and by the time the dock asks, what
    // it wanted to remember has already stopped.
    watchLastPlayed(container.read);
  });
  tearDown(() => container.dispose());

  test('nothing has played yet', () {
    expect(container.read(lastPlayedProvider), isNull);
  });

  test('what played is remembered after it stops', () {
    container.read(nowPlayingProvider.notifier).state =
        const NowPlaying(id: 'b1', kind: PlaybackKind.bank, name: 'Front Wash');
    container.read(nowPlayingProvider.notifier).state = null;

    final last = container.read(lastPlayedProvider);
    expect(last?.id, 'b1');
    expect(last?.name, 'Front Wash');
    expect(last?.kind, PlaybackKind.bank);
  });

  test('the most recent one wins', () {
    final notifier = container.read(nowPlayingProvider.notifier);
    notifier.state = const NowPlaying(id: 'b1', kind: PlaybackKind.bank, name: 'Front Wash');
    notifier.state = const NowPlaying(id: 'p1', kind: PlaybackKind.smartProgram, name: 'Első okos program');
    notifier.state = null;

    expect(container.read(lastPlayedProvider)?.id, 'p1');
    expect(container.read(lastPlayedProvider)?.kind, PlaybackKind.smartProgram);
  });

  group('program targets compare by value', () {
    // The player decides whether to re-trigger a running zone by comparing
    // targets, and the getters build a fresh object every call — without
    // value equality every save would restart the chase and jump the look.
    test('same id and kind are equal', () {
      expect(
        ProgramTarget.from(bankId: 'b1'),
        ProgramTarget.from(bankId: 'b1'),
      );
    });

    test('a bank and a chase with the same id are not', () {
      expect(
        ProgramTarget.from(bankId: 'x') == ProgramTarget.from(chaseId: 'x'),
        isFalse,
      );
    });

    test('a program reports the target of each zone', () {
      const program = SmartProgram(id: 'p', name: 'Test', baseBankId: 'b1', fasterChaseId: 'c9');
      expect(program.baseTarget, ProgramTarget.from(bankId: 'b1'));
      expect(program.fasterTarget, ProgramTarget.from(chaseId: 'c9'));
      expect(program.slowerTarget, isNull);
      // Editing an unrelated field leaves the targets equal, which is what
      // stops a save from restarting the chase.
      expect(program.copyWith(baseBpm: 140).baseTarget, program.baseTarget);
    });
  });
}
