import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/midi/midi_control_service.dart';
import '../core/midi/midi_input_message.dart';
import '../core/midi/midi_mapping_engine.dart';
import '../core/remote/trigger_actions.dart';
import '../core/widgets/log_scale.dart';
import '../models/midi_mapping.dart';
import 'artnet_providers.dart';
import 'bank_providers.dart';
import 'chase_providers.dart';
import 'color_override_providers.dart';
import 'movement_live_providers.dart';
import 'playback_providers.dart';
import 'smart_program_providers.dart';
import 'tempo_providers.dart';

const _uuid = Uuid();

/// Remembered controllers (device-level: they belong to this tablet, not
/// to a show).
const prefMidiControlDevices = 'midiControl.devices';

/// The project's MIDI mappings — see [MidiMapping].
final midiMappingsProvider = StateNotifierProvider<MidiMappingsNotifier, List<MidiMapping>>(
  (ref) => MidiMappingsNotifier(),
);

class MidiMappingsNotifier extends StateNotifier<List<MidiMapping>> {
  MidiMappingsNotifier() : super(const []);

  /// Adds [mapping], or replaces the one with its id. Any other mapping on
  /// the same control is dropped: one control, one job — otherwise a pad
  /// re-learned for something new would quietly keep doing the old thing too.
  MidiMapping save(MidiMapping mapping) {
    final withId = mapping.id.isEmpty
        ? MidiMapping(
            id: _uuid.v4(),
            trigger: mapping.trigger,
            action: mapping.action,
            targetKind: mapping.targetKind,
            targetId: mapping.targetId,
            param: mapping.param,
          )
        : mapping;
    final others = [for (final m in state) if (m.id != withId.id && m.trigger != withId.trigger) m];
    final index = state.indexWhere((m) => m.id == withId.id);
    if (index < 0) {
      state = [...others, withId];
    } else {
      // Keep its place in the list.
      final list = [...others];
      list.insert(index.clamp(0, list.length), withId);
      state = list;
    }
    return withId;
  }

  /// The mapping already bound to [trigger], other than [exceptId].
  MidiMapping? boundTo(MidiTrigger trigger, {String? exceptId}) {
    for (final m in state) {
      if (m.trigger == trigger && m.id != exceptId) return m;
    }
    return null;
  }

  void remove(String id) => state = [for (final m in state) if (m.id != id) m];

  void clear() => state = const [];

  void loadAll(List<MidiMapping> mappings) => state = mappings;
}

/// The saved controller list, loaded in `main()` before the first frame.
final initialMidiControlDevicesProvider = Provider<List<RememberedMidiDevice>>((ref) => const []);

List<RememberedMidiDevice> midiControlDevicesFromPrefs(List<String>? raw) => [
  for (final entry in raw ?? const <String>[]) ?RememberedMidiDevice.decode(entry),
];

/// The controller input and what it drives. Created at startup (see
/// [watchMidiControl]) so a remembered controller works without opening
/// Setup first.
final midiControlProvider = Provider<MidiControlController>((ref) {
  final controller = MidiControlController(ref.read, MidiControlService());
  ref.onDispose(controller.dispose);
  return controller;
});

/// Brings the controller input up at startup.
void watchMidiControl(ReadProvider read) {
  final controller = read(midiControlProvider);
  unawaited(controller.service.start(read(initialMidiControlDevicesProvider)));
}

class MidiControlController {
  final ReadProvider read;
  final MidiControlService service;
  final MidiMappingEngine _engine = MidiMappingEngine();
  final TapTempo _tap = TapTempo();
  Timer? _restartDebounce;

  /// The mapping that fired last, for the settings screen to flash its row.
  final ValueNotifier<String?> lastFiredId = ValueNotifier(null);

  /// What the last action reported ("Started Front wash", an error…).
  final ValueNotifier<String?> lastResult = ValueNotifier(null);

  MidiControlController(this.read, this.service) {
    service.onMessage = handle;
    service.onRememberedChanged = (devices) async {
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setStringList(prefMidiControlDevices, [for (final d in devices) d.encode()]);
      } catch (_) {}
    };
  }

  /// Runs every mapping [message] fires.
  void handle(MidiInputMessage message) {
    for (final firing in _engine.handle(message, read(midiMappingsProvider))) {
      lastFiredId.value = firing.mapping.id;
      unawaited(_run(firing));
    }
  }

  Future<void> _run(MidiFiring firing) async {
    try {
      final result = await runMidiAction(read, firing.mapping, firing.value, tap: _tap, onTiming: _scheduleRestart);
      if (result != null) lastResult.value = result;
    } catch (e) {
      lastResult.value = e is StateError ? e.message : e.toString();
    }
  }

  /// A fader sweep sends dozens of values; re-firing the running chase on
  /// each one would keep kicking it back to step 1. Wait until it settles.
  void _scheduleRestart() {
    _restartDebounce?.cancel();
    _restartDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(restartActiveTrigger(read, timingOnly: true));
    });
  }

  void dispose() {
    _restartDebounce?.cancel();
    service.dispose();
    lastFiredId.dispose();
    lastResult.dispose();
  }
}

/// Does what [mapping] says, through the same shared actions a Dashboard
/// tile, the control dock and the remote endpoint use. [value] is the
/// control's position (0..1) for a continuous action. Returns a short
/// status message, or null for a continuous move (no message per step).
///
/// [onTiming] is called after the step speed or fade changed, so the caller
/// can re-fire the running chase once the fader stops moving.
Future<String?> runMidiAction(
  ReadProvider read,
  MidiMapping mapping,
  double value, {
  TapTempo? tap,
  void Function()? onTiming,
}) async {
  switch (mapping.action) {
    case MidiActionKind.playTarget:
      final id = mapping.targetId;
      if (id == null) return 'Nothing picked for this control';
      switch (mapping.targetKind ?? MidiTargetKind.bank) {
        case MidiTargetKind.smart:
          return toggleSmartProgramById(read, id);
        case MidiTargetKind.bank:
          final banks = read(banksProvider).where((b) => b.id == id);
          if (banks.isEmpty) return 'Bank no longer exists';
          return togglePlayable(read, id: id, isBank: true, name: banks.first.name);
        case MidiTargetKind.chase:
          final chases = read(chasesProvider).where((c) => c.id == id);
          if (chases.isEmpty) return 'Chase no longer exists';
          return togglePlayable(read, id: id, isBank: false, name: chases.first.name);
      }
    case MidiActionKind.resume:
      return resumeLastPlayed(read);
    case MidiActionKind.stop:
      stopPlayback(read);
      return 'Stopped';
    case MidiActionKind.blackout:
      await blackoutEverything(read);
      return 'Blackout';
    case MidiActionKind.beatSync:
      return setBeatSync(read);
    case MidiActionKind.predict:
      return setBeatPrediction(read);
    case MidiActionKind.autoFade:
      return setAutoFade(read);
    case MidiActionKind.dropout:
      return setDropout(read);
    case MidiActionKind.tapTempo:
      final bpm = (tap ?? TapTempo()).tap(DateTime.now());
      if (bpm == null) return 'Tap…';
      read(tempoProvider.notifier).setBpm(bpm);
      onTiming?.call();
      return 'Tap ${bpm.round()} BPM';
    case MidiActionKind.color:
      final param = mapping.param;
      if (param == null || param == 'off') return setLiveColor(read, off: true);
      return setLiveColor(read, name: param);
    case MidiActionKind.grandMaster:
      read(grandMasterProvider.notifier).set(value);
      return null;
    case MidiActionKind.stepSpeed:
      read(tempoProvider.notifier).setStepSeconds(stepSpeedScale.valueAt(value));
      onTiming?.call();
      return null;
    case MidiActionKind.fadeTime:
      read(tempoProvider.notifier).setFadeSeconds(fadeTimeScale.valueAt(value));
      onTiming?.call();
      return null;
    case MidiActionKind.movementSize:
      read(movementLiveProvider.notifier).set(size: value * 2);
      return null;
    case MidiActionKind.movementSpeed:
      read(movementLiveProvider.notifier).set(speed: movementSpeedScale.valueAt(value));
      return null;
    case MidiActionKind.movementShift:
      read(movementLiveProvider.notifier).set(shift: value);
      return null;
    case MidiActionKind.movementSmooth:
      read(movementLiveProvider.notifier).set(smooth: value);
      return null;
    case MidiActionKind.movementReset:
      read(movementLiveProvider.notifier).reset();
      return 'Movement knobs neutral';
  }
}

/// Mirrors the Movement strip's speed knob (×0.25–×4, log-spaced).
const movementSpeedScale = LogScale(min: 0.25, max: 4.0);

/// Keeps the colour list reachable from here for the picker.
List<String> get midiColorIds => [for (final c in liveColors) c.id];

/// The name a [MidiActionKind.playTarget] mapping's target goes by now, or
/// null if it's gone.
String? midiTargetName(ReadProvider read, MidiMapping mapping) {
  final id = mapping.targetId;
  if (id == null) return null;
  switch (mapping.targetKind ?? MidiTargetKind.bank) {
    case MidiTargetKind.bank:
      for (final b in read(banksProvider)) {
        if (b.id == id) return b.name;
      }
    case MidiTargetKind.chase:
      for (final c in read(chasesProvider)) {
        if (c.id == id) return c.name;
      }
    case MidiTargetKind.smart:
      for (final p in read(smartProgramsProvider)) {
        if (p.id == id) return p.name;
      }
  }
  return null;
}
