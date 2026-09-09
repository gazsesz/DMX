import 'package:dmx_controller/models/bank.dart';
import 'package:dmx_controller/state/bank_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drag-to-reorder inside a bank goes through `moveSlot`, and the index
/// shifting there is easy to get subtly wrong in one direction only.
void main() {
  late ProviderContainer container;
  late String bankId;

  setUp(() {
    container = ProviderContainer();
    final notifier = container.read(banksProvider.notifier);
    notifier.loadAll([
      Bank(id: 'b1', name: 'Bank 1', sceneSlots: ['a', 'b', 'c', null, 'd']),
    ]);
    bankId = 'b1';
  });

  tearDown(() => container.dispose());

  List<String?> slots() => container.read(banksProvider).first.sceneSlots;

  test('moving a scene later puts it where the target was', () {
    // Drop 'a' onto 'c' (index 2).
    container.read(banksProvider.notifier).moveSlot(bankId, 0, 2);
    expect(slots(), ['b', 'c', 'a', null, 'd']);
  });

  test('moving a scene earlier puts it where the target was', () {
    // Drop 'd' (index 4) onto 'b' (index 1).
    container.read(banksProvider.notifier).moveSlot(bankId, 4, 1);
    expect(slots(), ['a', 'd', 'b', 'c', null]);
  });

  test('keeps the bank size and its empty slots', () {
    container.read(banksProvider.notifier).moveSlot(bankId, 0, 4);
    final result = slots();
    expect(result.length, 5);
    expect(result.where((s) => s == null).length, 1);
    expect(result.whereType<String>().toSet(), {'a', 'b', 'c', 'd'});
  });

  test('a no-op move and out-of-range indexes leave the bank alone', () {
    container.read(banksProvider.notifier).moveSlot(bankId, 2, 2);
    expect(slots(), ['a', 'b', 'c', null, 'd']);
    container.read(banksProvider.notifier).moveSlot(bankId, 0, 99);
    expect(slots(), ['a', 'b', 'c', null, 'd']);
  });
}
