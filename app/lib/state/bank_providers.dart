import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/bank.dart';

const _uuid = Uuid();
const defaultBankSize = 16;

final banksProvider = StateNotifierProvider<BanksNotifier, List<Bank>>((ref) {
  return BanksNotifier();
});

/// Which bank the Banks screen shows as selected — lifted out of that
/// screen's own State so it's part of the project rather than something
/// that resets to the first bank whenever the show is saved and reloaded
/// (or the app restarts). Creating a bank — the "New" button, or a preset
/// like Beat Flash — points this at the new bank; it never causes anything
/// to actually play, since something else may already be live.
final selectedBankIdProvider = StateProvider<String?>((ref) => null);

class BanksNotifier extends StateNotifier<List<Bank>> {
  BanksNotifier()
    : super([
        Bank(id: _uuid.v4(), name: 'Bank 1', sceneSlots: List.filled(defaultBankSize, null)),
      ]);

  /// [name] and [slots] let a preset mint a bank that is already the right
  /// size and called the right thing, instead of an empty "Bank N" the
  /// caller then has to rename and resize in two more state updates.
  /// [isBeatFlash] tags a bank built by the Beat Flash preset — see [Bank].
  Bank addBank({String? name, int? slots, bool isBeatFlash = false}) {
    final bank = Bank(
      id: _uuid.v4(),
      name: name ?? 'Bank ${state.length + 1}',
      sceneSlots: List.filled(slots ?? defaultBankSize, null),
      isBeatFlash: isBeatFlash,
    );
    state = [...state, bank];
    return bank;
  }

  /// Returns the copy, so the caller can switch to it.
  Bank? duplicate(String id) {
    final source = state.where((b) => b.id == id);
    if (source.isEmpty) return null;
    final original = source.first;
    final copy = Bank(
      id: _uuid.v4(),
      name: '${original.name} Copy',
      sceneSlots: [...original.sceneSlots],
      isBeatFlash: original.isBeatFlash,
      flashFadeOutMs: original.flashFadeOutMs,
      ownTiming: original.ownTiming,
      holdMs: original.holdMs,
      fadeMs: original.fadeMs,
    );
    state = [...state, copy];
    return copy;
  }

  /// Sets whether [id] plays at its own Hold/Fade, and what they are — see
  /// [Bank.ownTiming].
  void setTiming(String id, {bool? ownTiming, int? holdMs, int? fadeMs}) {
    state = [
      for (final b in state)
        if (b.id == id)
          b.copyWith(
            ownTiming: ownTiming,
            holdMs: holdMs?.clamp(20, 10000),
            fadeMs: fadeMs?.clamp(0, 10000),
          )
        else
          b,
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

  /// Sets the lit→dark fade-out for a Beat Flash bank's [BeatRate.flash]
  /// playback — see [Bank.flashFadeOutMs].
  void setFlashFadeOut(String id, int ms) {
    state = [
      for (final b in state)
        if (b.id == id) b.copyWith(flashFadeOutMs: ms.clamp(0, 5000)) else b,
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
