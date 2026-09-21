import 'package:dmx_controller/models/bank.dart';
import 'package:dmx_controller/state/bank_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// `isBeatFlash` and `flashFadeOutMs` are what tells the player a bank is a
/// Beat Flash pair rather than an ordinary one — both have to survive a
/// save/load round trip, and stay off/zero for every bank that predates them.
void main() {
  test('an ordinary bank defaults to not-a-flash-bank with no fade-out', () {
    const bank = Bank(id: 'b1', name: 'Bank 1', sceneSlots: [null, null]);
    expect(bank.isBeatFlash, isFalse);
    expect(bank.flashFadeOutMs, 0);
  });

  test('round-trips isBeatFlash and flashFadeOutMs through JSON', () {
    const bank = Bank(
      id: 'b1',
      name: 'Beat Flash',
      sceneSlots: ['out', 'up'],
      isBeatFlash: true,
      flashFadeOutMs: 150,
    );
    final restored = Bank.fromJson(bank.toJson());
    expect(restored.isBeatFlash, isTrue);
    expect(restored.flashFadeOutMs, 150);
    expect(restored.sceneSlots, ['out', 'up']);
  });

  test('a bank saved before these fields existed loads with the old defaults', () {
    final restored = Bank.fromJson({
      'id': 'b1',
      'name': 'Bank 1',
      'sceneSlots': ['a', null],
    });
    expect(restored.isBeatFlash, isFalse);
    expect(restored.flashFadeOutMs, 0);
  });

  test('copyWith leaves isBeatFlash and flashFadeOutMs alone unless asked', () {
    const bank = Bank(id: 'b1', name: 'Beat Flash', sceneSlots: [null, null], isBeatFlash: true, flashFadeOutMs: 80);
    final renamed = bank.copyWith(name: 'Renamed');
    expect(renamed.isBeatFlash, isTrue);
    expect(renamed.flashFadeOutMs, 80);
  });

  group('BanksNotifier.setFlashFadeOut', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      container.read(banksProvider.notifier).loadAll([
        const Bank(id: 'b1', name: 'Beat Flash', sceneSlots: [null, null], isBeatFlash: true),
      ]);
    });

    tearDown(() => container.dispose());

    test('sets the fade-out on the named bank only', () {
      container.read(banksProvider.notifier).loadAll([
        const Bank(id: 'b1', name: 'Beat Flash', sceneSlots: [null, null], isBeatFlash: true),
        const Bank(id: 'b2', name: 'Other', sceneSlots: [null, null]),
      ]);
      container.read(banksProvider.notifier).setFlashFadeOut('b1', 200);
      final banks = {for (final b in container.read(banksProvider)) b.id: b};
      expect(banks['b1']!.flashFadeOutMs, 200);
      expect(banks['b2']!.flashFadeOutMs, 0);
    });

    test('clamps to a sane range rather than trusting the caller', () {
      container.read(banksProvider.notifier).setFlashFadeOut('b1', -50);
      expect(container.read(banksProvider).first.flashFadeOutMs, 0);
      container.read(banksProvider.notifier).setFlashFadeOut('b1', 999999);
      expect(container.read(banksProvider).first.flashFadeOutMs, 5000);
    });
  });
}
