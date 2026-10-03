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
      slotTimings: [...original.slotTimings],
    );
    state = [...state, copy];
    return copy;
  }

  /// Marks [id] as a Beat Flash bank (dark/lit pairs, flashing) or not —
  /// for a bank built by hand, or one from before the flag was kept on a
  /// copy.
  void setBeatFlash(String id, bool value) {
    state = [
      for (final b in state)
        if (b.id == id) b.copyWith(isBeatFlash: value) else b,
    ];
  }

  /// Sets whether [id] plays at its own Hold/Fade, and what they are — see
  /// [Bank.ownTiming].
  void setTiming(String id, {bool? ownTiming, int? holdMs, int? fadeMs}) {
    state = [
      for (final b in state)
        if (b.id == id)
          b.copyWith(
            ownTiming: ownTiming,
            holdMs: holdMs?.clamp(20, 60000),
            fadeMs: fadeMs?.clamp(0, 120000),
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

  /// Puts [sceneId] in a slot. Swapping in another scene keeps the step's
  /// own timing (it belongs to the step, not the scene); clearing the slot
  /// drops it, since an empty slot isn't a step any more.
  void setSlot(String bankId, int slotIndex, String? sceneId) {
    state = [
      for (final b in state)
        if (b.id == bankId)
          () {
            final updated = b.copyWith(
              sceneSlots: [for (var i = 0; i < b.sceneSlots.length; i++) i == slotIndex ? sceneId : b.sceneSlots[i]],
            );
            return sceneId == null ? _withSlotTiming(updated, slotIndex, null) : updated;
          }()
        else
          b,
    ];
  }

  /// Puts [sceneId] in the first free slot after [afterSlot] (wrapping round
  /// to the start), so a copy lands next to the scene it was made from —
  /// and grows the bank by one slot when every slot is taken. Returns the
  /// slot used, or null when the bank no longer exists.
  int? placeAfter(String bankId, int? afterSlot, String sceneId) {
    final bank = state.where((b) => b.id == bankId).firstOrNull;
    if (bank == null) return null;
    final slots = bank.sceneSlots;
    final start = afterSlot == null ? 0 : (afterSlot + 1).clamp(0, slots.length);
    final order = [for (var i = start; i < slots.length; i++) i, for (var i = 0; i < start; i++) i];
    final free = order.where((i) => slots[i] == null).firstOrNull;
    if (free != null) {
      setSlot(bankId, free, sceneId);
      return free;
    }
    resize(bankId, slots.length + 1);
    setSlot(bankId, slots.length, sceneId);
    return slots.length;
  }

  /// Gives the step in [slotIndex] its own Hold/Fade, or with null puts it
  /// back to following the bank — see [Bank.slotTimings].
  void setSlotTiming(String bankId, int slotIndex, SlotTiming? timing) {
    state = [
      for (final b in state)
        if (b.id == bankId) _withSlotTiming(b, slotIndex, timing) else b,
    ];
  }

  /// Puts every step of [bankId] back to following the bank.
  void clearSlotTimings(String bankId) {
    state = [
      for (final b in state)
        if (b.id == bankId) b.copyWith(slotTimings: const []) else b,
    ];
  }

  static Bank _withSlotTiming(Bank bank, int slotIndex, SlotTiming? timing) {
    if (slotIndex < 0 || slotIndex >= bank.sceneSlots.length) return bank;
    final timings = List<SlotTiming?>.generate(bank.sceneSlots.length, bank.timingAt);
    timings[slotIndex] = timing == null
        ? null
        : SlotTiming(holdMs: timing.holdMs.clamp(20, 60000), fadeMs: timing.fadeMs.clamp(0, 120000));
    return bank.copyWith(slotTimings: timings.any((t) => t != null) ? timings : const []);
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
            // A step's own timing travels with it.
            slotTimings: () {
              if (!b.hasStepTimings || fromSlot < 0 || fromSlot >= b.sceneSlots.length ||
                  toSlot < 0 || toSlot >= b.sceneSlots.length) {
                return b.slotTimings;
              }
              final timings = List<SlotTiming?>.generate(b.sceneSlots.length, b.timingAt);
              final moved = timings.removeAt(fromSlot);
              timings.insert(toSlot, moved);
              return timings;
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
