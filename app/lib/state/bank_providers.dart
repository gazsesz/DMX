import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/bank.dart';

const _uuid = Uuid();
const defaultBankSize = 16;

final banksProvider = StateNotifierProvider<BanksNotifier, List<Bank>>((ref) {
  return BanksNotifier();
});

class BanksNotifier extends StateNotifier<List<Bank>> {
  BanksNotifier()
    : super([
        Bank(id: _uuid.v4(), name: 'Bank 1', sceneSlots: List.filled(defaultBankSize, null)),
      ]);

  Bank addBank() {
    final bank = Bank(
      id: _uuid.v4(),
      name: 'Bank ${state.length + 1}',
      sceneSlots: List.filled(defaultBankSize, null),
    );
    state = [...state, bank];
    return bank;
  }

  void duplicate(String id) {
    final source = state.where((b) => b.id == id);
    if (source.isEmpty) return;
    final copy = source.first;
    state = [
      ...state,
      Bank(id: _uuid.v4(), name: '${copy.name} Copy', sceneSlots: [...copy.sceneSlots]),
    ];
  }

  void rename(String id, String name) {
    state = [
      for (final b in state)
        if (b.id == id) b.copyWith(name: name) else b,
    ];
  }

  void resize(String id, int newSize) {
    state = [
      for (final b in state)
        if (b.id == id) b.resized(newSize) else b,
    ];
  }

  void setSlot(String bankId, int slotIndex, String? sceneId) {
    state = [
      for (final b in state)
        if (b.id == bankId)
          b.copyWith(sceneSlots: [for (var i = 0; i < b.sceneSlots.length; i++) i == slotIndex ? sceneId : b.sceneSlots[i]])
        else
          b,
    ];
  }

  /// Moves the scene in [fromSlot] to sit at [toSlot], shuffling the slots
  /// in between along — the bank keeps its size, so playback order changes
  /// without any slot being lost or created.
  void moveSlot(String bankId, int fromSlot, int toSlot) {
    if (fromSlot == toSlot) return;
    state = [
      for (final b in state)
        if (b.id == bankId)
          b.copyWith(
            sceneSlots: () {
              final slots = [...b.sceneSlots];
              if (fromSlot < 0 || fromSlot >= slots.length || toSlot < 0 || toSlot >= slots.length) {
                return slots;
              }
              final moved = slots.removeAt(fromSlot);
              slots.insert(toSlot, moved);
              return slots;
            }(),
          )
        else
          b,
    ];
  }

  void remove(String id) {
    state = state.where((b) => b.id != id).toList();
  }

  void loadAll(List<Bank> banks) {
    state = banks;
  }

  void reset() {
    state = [Bank(id: _uuid.v4(), name: 'Bank 1', sceneSlots: List.filled(defaultBankSize, null))];
  }
}
