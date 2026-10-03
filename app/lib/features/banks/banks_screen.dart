import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/generator/program_generator.dart';
import '../../core/playback/chase_player.dart';
import '../../core/playback/scene_output.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/color_picker_dialog.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/control_dock.dart';
import '../../core/widgets/fixture_select.dart';
import '../../core/widgets/log_scale.dart';
import '../../core/widgets/layer_picker_sheet.dart';
import '../../core/widgets/node_status_action.dart';
import '../../core/widgets/save_project_action.dart';
import '../../core/widgets/show_items_actions.dart';
import '../../models/bank.dart';
import '../../models/dashboard_trigger.dart';
import '../../models/layer.dart';
import '../../models/scene.dart';
import '../../state/artnet_providers.dart';
import '../../state/audio_providers.dart';
import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';
import '../../state/control_dock_providers.dart';
import '../../state/dashboard_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/layer_providers.dart';
import '../../state/playback_providers.dart';
import '../../state/scene_providers.dart';
import '../../state/tempo_providers.dart';
import '../scenes/scene_editor_screen.dart';
import '../scenes/scenes_screen.dart';
import 'program_generator_screen.dart';

const _uuid = Uuid();

class BanksScreen extends ConsumerStatefulWidget {
  const BanksScreen({super.key});

  @override
  ConsumerState<BanksScreen> createState() => _BanksScreenState();
}

class _BanksScreenState extends ConsumerState<BanksScreen> {
  /// The slot the user last fired by hand — so tapping a scene shows which
  /// one is live even when the bank isn't running as a chase.
  int? _manualSlot;

  /// "Edit slots" mode: a tap on a slot opens its menu instead of playing it.
  bool _editSlots = false;

  final _bankChipsScroll = ScrollController();

  @override
  void dispose() {
    _bankChipsScroll.dispose();
    super.dispose();
  }

  void _selectBank(String bankId) {
    ref.read(selectedBankIdProvider.notifier).state = bankId;
    setState(() => _manualSlot = null);
  }

  /// Every bank in a searchable list — the way to a bank when there are
  /// more than the chip box shows.
  Future<void> _showAllBanks(List<Bank> banks, String selectedId) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.panel,
      showDragHandle: true,
      builder: (context) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final shown = banks.where((b) => b.name.toLowerCase().contains(query.toLowerCase())).toList();
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.75,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        autofocus: false,
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search banks'),
                        onChanged: (v) => setSheetState(() => query = v),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final bank in shown)
                            ListTile(
                              selected: bank.id == selectedId,
                              selectedTileColor: AppColors.panel2,
                              leading: Icon(
                                bank.isBeatFlash ? Icons.flash_on : Icons.grid_view,
                                size: 18,
                                color: bank.isBeatFlash ? AppColors.accent : AppColors.textDim,
                              ),
                              title: Text(bank.name),
                              subtitle: Text(
                                '${bank.sceneSlots.where((s) => s != null).length}/${bank.sceneSlots.length} scenes',
                                style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
                              ),
                              onTap: () => Navigator.pop(context, bank.id),
                            ),
                          if (shown.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('No bank by that name', style: TextStyle(color: AppColors.textFaint)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (picked != null && mounted) _selectBank(picked);
  }

  bool _isThisBankRunning(Bank bank) => layersPlaying(ref.read, bank.id).contains(layer1Id);

  /// Whether [bank] is currently running on any layer other than Layer 1 —
  /// drives the "run on another layer" icon's active color.
  bool _isThisBankRunningOnAnyOtherLayer(Bank bank) {
    for (final layer in ref.read(layersProvider)) {
      if (layer.id == layer1Id) continue;
      final current = ref.read(nowPlayingForLayerProvider(layer.id));
      if (current?.kind == PlaybackKind.bank && current?.id == bank.id) return true;
    }
    return false;
  }

  void _toggleRun(Bank bank) {
    if (_isThisBankRunning(bank)) {
      stopLayer(ref.read, layer1Id);
      return;
    }
    // The same start as the layer picker and a Dashboard tile, so a bank
    // plays the same wherever it's fired from.
    final error = runBankOnLayer(ref.read, bank: bank, layerId: layer1Id);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _manualSlot = null);
  }

  /// Everything running follows the switch live — no re-fire, which used to
  /// reach only a bank run from this screen and left a chase started
  /// elsewhere stuck waiting for beats.
  Future<void> _setBeatSync(bool value) async {
    final error = await ref.read(beatSyncEnabledProvider.notifier).setEnabled(value);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  /// This bank's own Hold/Fade — or the choice to follow the dock's, which
  /// is where the readout used to send you whatever you wanted to change.
  Future<void> _editBankTiming(String bankId) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.panel,
      showDragHandle: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final bank = ref.watch(banksProvider).where((b) => b.id == bankId).firstOrNull;
          if (bank == null) return const SizedBox.shrink();
          final tempo = ref.watch(tempoProvider);
          final beatSync = ref.watch(beatSyncEnabledProvider);
          final notifier = ref.read(banksProvider.notifier);
          void restart() => restartBankEverywhere(ref.read, bankId);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${bank.name} — Timing', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Own timing for this bank'),
                    subtitle: Text(
                      bank.ownTiming
                          ? 'Plays at the Hold/Fade below, wherever it runs'
                          : 'Follows the dock: Hold ${tempo.stepSeconds.toStringAsFixed(2)}s · '
                                'Fade ${tempo.effectiveFadeSeconds.toStringAsFixed(2)}s${tempo.autoFade ? ' (auto)' : ''}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textFaint),
                    ),
                    value: bank.ownTiming,
                    onChanged: (v) {
                      notifier.setTiming(bankId, ownTiming: v);
                      restart();
                    },
                  ),
                  if (bank.ownTiming) ...[
                    Text(
                      beatSync ? 'Hold ${_seconds(bank.holdMs)} — Beat Sync is on, steps follow the beat' : 'Hold ${_seconds(bank.holdMs)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
                    ),
                    Slider(
                      value: holdTimeScale.positionOf(bank.holdMs / 1000),
                      onChanged: (p) => notifier.setTiming(bankId, holdMs: (holdTimeScale.valueAt(p) * 1000).round()),
                      onChangeEnd: (_) => restart(),
                    ),
                    Text('Fade ${_seconds(bank.fadeMs)}', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
                    Slider(
                      value: fadeTimeScale.positionOf(bank.fadeMs / 1000),
                      activeColor: AppColors.accent2,
                      onChanged: (p) => notifier.setTiming(bankId, fadeMs: (fadeTimeScale.valueAt(p) * 1000).round()),
                      onChangeEnd: (_) => restart(),
                    ),
                  ],
                  if (bank.hasStepTimings) ...[
                    const Divider(height: 20),
                    Row(
                      children: [
                        const Icon(Icons.timer_outlined, size: 16, color: AppColors.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${bank.slotTimings.where((t) => t != null).length} step(s) have their own timing, '
                            'which wins over this',
                            style: const TextStyle(fontSize: 11.5, color: AppColors.textDim),
                          ),
                        ),
                        TextButton(
                          onPressed: () => notifier.clearSlotTimings(bankId),
                          child: const Text('Reset all steps'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.tune, size: 16),
                      label: const Text('App-wide timing (dock)'),
                      onPressed: () {
                        Navigator.pop(context);
                        ref.read(controlDockProvider.notifier).toggleExpanded();
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static String _seconds(int ms) => '${(ms / 1000).toStringAsFixed(2)}s';

  /// Builds the ready-made beat-flash program: a two-scene bank — rig out,
  /// rig at full — armed for Beat Sync at the Flash rate, which is the one
  /// combination that gives a stab on each beat instead of a square wave
  /// sitting at 50% duty. One tap, rather than building two scenes by hand
  /// and then remembering which of the four beat rates does this.
  ///
  /// Asks for the flash colour up front — white by default, but a tap away
  /// from anything else — since a bank editor buried two screens deep is not
  /// where anyone would think to look to change it. The "Up" scene can still
  /// be split into differently-coloured groups afterwards for a flash where
  /// the lamps don't all match.
  /// The colour half of the Beat Flash preset: one colour for every flash,
  /// or a fresh random one on each — the whole rig alike, or every lamp its
  /// own. Null on cancel.
  Future<({FlashColorMode mode, List<int> color, int flashCount})?> _askBeatFlashColors() {
    var mode = FlashColorMode.single;
    var color = const [255, 255, 255];
    var flashCount = 8;
    return showDialog<({FlashColorMode mode, List<int> color, int flashCount})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.panel,
          title: const Text('Beat Flash colours'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioGroup<FlashColorMode>(
                groupValue: mode,
                onChanged: (v) => setDialogState(() => mode = v ?? mode),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final m in FlashColorMode.values)
                      RadioListTile<FlashColorMode>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: m,
                        title: Text(m.label),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (mode == FlashColorMode.single)
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Color.fromARGB(255, color[0], color[1], color[2]),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: () async {
                        final picked = await showColorPickerDialog(context, initial: color);
                        if (picked != null) setDialogState(() => color = picked);
                      },
                      child: const Text('Pick colour…'),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    const Expanded(child: Text('Flashes before it repeats')),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                      onPressed: flashCount > 2 ? () => setDialogState(() => flashCount--) : null,
                    ),
                    SizedBox(width: 24, child: Text('$flashCount', textAlign: TextAlign.center)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      onPressed: flashCount < 32 ? () => setDialogState(() => flashCount++) : null,
                    ),
                  ],
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, (mode: mode, color: color, flashCount: flashCount)),
              child: const Text('Next'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addBeatFlashBank() async {
    final fixtures = ref.read(patchedFixturesProvider);
    if (fixtures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No patched fixtures — patch your lamps first')),
      );
      return;
    }

    final options = await _askBeatFlashColors();
    if (options == null || !mounted) return;
    // Which lamps flash — the rest of the rig is left to whatever else is
    // playing, instead of being blacked out on every beat.
    final chosen = await showFixtureSelectDialog(context, fixtures: fixtures, title: 'Which fixtures flash?');
    if (chosen == null || !mounted) return;

    final List<Scene> scenes;
    final List<String> slots;
    if (options.mode == FlashColorMode.single) {
      scenes = buildBeatFlashScenes(fixtures: chosen, idGenerator: () => _uuid.v4(), color: options.color);
      slots = [for (final s in scenes) s.id];
    } else {
      final built = buildRandomBeatFlash(
        fixtures: chosen,
        idGenerator: () => _uuid.v4(),
        mode: options.mode,
        flashCount: options.flashCount,
      );
      scenes = built.scenes;
      slots = built.slots;
    }
    final sceneNotifier = ref.read(scenesProvider.notifier);
    for (final scene in scenes) {
      sceneNotifier.upsert(scene);
    }

    final banksNotifier = ref.read(banksProvider.notifier);
    final taken = {for (final b in ref.read(banksProvider)) b.name};
    var name = 'Beat Flash';
    for (var n = 2; taken.contains(name); n++) {
      name = 'Beat Flash $n';
    }
    final bank = banksNotifier.addBank(name: name, slots: slots.length, isBeatFlash: true);
    for (var i = 0; i < slots.length; i++) {
      banksNotifier.setSlot(bank.id, i, slots[i]);
    }

    // No app-wide switch to Flash any more: a Beat Flash bank steps at the
    // Flash rate by itself, and flipping the shared rate made everything
    // else running on the other layers flash along with it.
    ref.read(selectedBankIdProvider.notifier).state = bank.id;
    setState(() => _manualSlot = null);
    // Arms the mic through the same path as the switch below, so a denied
    // or busy microphone reports itself the way it does everywhere else.
    await _setBeatSync(true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"$name" ready — hit Run Bank and it flashes on every beat')),
    );
  }

  static const _newSceneSentinel = '__new__';
  static const _stepTimingSentinel = '__timing__';
  static const _duplicateSceneSentinel = '__duplicate__';

  /// One step's own Hold/Fade. Switched off, the step follows the bank
  /// again (the bank's own timing, or the dock's) — that is the reset.
  Future<void> _editSlotTiming(String bankId, int slotIndex) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.panel,
      showDragHandle: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final bank = ref.watch(banksProvider).where((b) => b.id == bankId).firstOrNull;
          if (bank == null || slotIndex >= bank.sceneSlots.length) return const SizedBox.shrink();
          final tempo = ref.watch(tempoProvider);
          final beatSync = ref.watch(beatSyncEnabledProvider);
          final notifier = ref.read(banksProvider.notifier);
          final own = bank.timingAt(slotIndex);
          final inheritedHoldMs = bank.ownTiming ? bank.holdMs : (tempo.stepSeconds * 1000).round();
          final inheritedFadeMs = bank.ownTiming ? bank.fadeMs : (tempo.effectiveFadeSeconds * 1000).round();
          final inheritedFrom = bank.ownTiming ? 'the bank' : 'the dock';
          final sceneName =
              ref.watch(scenesProvider).where((s) => s.id == bank.sceneSlots[slotIndex]).firstOrNull?.name ?? 'Empty';
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Step ${slotIndex + 1} · $sceneName — Timing',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Own timing for this step'),
                    subtitle: Text(
                      own != null
                          ? 'Wins over ${bank.name}\'s and the dock\'s timing, wherever the bank plays'
                          : 'Follows $inheritedFrom: Hold ${_seconds(inheritedHoldMs)} · Fade ${_seconds(inheritedFadeMs)}',
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textFaint),
                    ),
                    value: own != null,
                    onChanged: (v) => notifier.setSlotTiming(
                      bankId,
                      slotIndex,
                      v ? SlotTiming(holdMs: inheritedHoldMs, fadeMs: inheritedFadeMs) : null,
                    ),
                  ),
                  if (own != null) ...[
                    Text(
                      beatSync
                          ? 'Hold ${_seconds(own.holdMs)} — Beat Sync is on, steps follow the beat'
                          : 'Hold ${_seconds(own.holdMs)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
                    ),
                    Slider(
                      value: holdTimeScale.positionOf(own.holdMs / 1000),
                      onChanged: (p) => notifier.setSlotTiming(
                        bankId,
                        slotIndex,
                        own.copyWith(holdMs: (holdTimeScale.valueAt(p) * 1000).round()),
                      ),
                    ),
                    Text('Fade ${_seconds(own.fadeMs)}', style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
                    Slider(
                      value: fadeTimeScale.positionOf(own.fadeMs / 1000),
                      activeColor: AppColors.accent2,
                      onChanged: (p) => notifier.setSlotTiming(
                        bankId,
                        slotIndex,
                        own.copyWith(fadeMs: (fadeTimeScale.valueAt(p) * 1000).round()),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.restart_alt, size: 16),
                        label: Text('Reset — follow $inheritedFrom again'),
                        onPressed: () => notifier.setSlotTiming(bankId, slotIndex, null),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Fills a slot: pick an existing scene, or build one right here.
  ///
  /// Creating from the slot is the point of folding the Scenes screen into
  /// this one — a new scene lands in the slot you started from instead of
  /// in a list you then have to go and drag from.
  Future<void> _pickScene(Bank bank, int slotIndex) async {
    final scenes = ref.read(scenesProvider);
    final chosen = await showDialog<String?>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: AppColors.panel,
        title: Text('Slot ${slotIndex + 1}'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _newSceneSentinel),
            child: const Row(
              children: [
                Icon(Icons.add, size: 18, color: AppColors.accent),
                SizedBox(width: 8),
                Text('New scene…', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          if (bank.sceneSlots[slotIndex] != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, _duplicateSceneSentinel),
              child: const Row(
                children: [
                  Icon(Icons.copy_outlined, size: 18, color: AppColors.textDim),
                  SizedBox(width: 8),
                  Text('Duplicate scene into the next free slot'),
                ],
              ),
            ),
          if (bank.sceneSlots[slotIndex] != null && !bank.isBeatFlash)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, _stepTimingSentinel),
              child: Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 18,
                    color: bank.timingAt(slotIndex) != null ? AppColors.accent : AppColors.textDim,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    bank.timingAt(slotIndex) == null
                        ? 'Step timing…'
                        : 'Step timing · ${_seconds(bank.timingAt(slotIndex)!.holdMs)} / ${_seconds(bank.timingAt(slotIndex)!.fadeMs)}',
                  ),
                ],
              ),
            ),
          if (bank.sceneSlots[slotIndex] != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Clear slot', style: TextStyle(color: AppColors.danger)),
            ),
          if (scenes.isNotEmpty) const Divider(height: 8),
          for (final scene in scenes)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, scene.id),
              child: Text(scene.name),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;

    if (chosen == _duplicateSceneSentinel) {
      final sourceId = bank.sceneSlots[slotIndex];
      if (sourceId == null) return;
      final copy = ref.read(scenesProvider.notifier).duplicate(sourceId);
      if (copy == null) return;
      final banks = ref.read(banksProvider.notifier);
      final slot = banks.placeAfter(bank.id, slotIndex, copy.id);
      // The copy plays the way the original does.
      final timing = bank.timingAt(slotIndex);
      if (slot != null && timing != null) banks.setSlotTiming(bank.id, slot, timing);
      return;
    }
    if (chosen == _stepTimingSentinel) {
      await _editSlotTiming(bank.id, slotIndex);
      return;
    }
    if (chosen == _newSceneSentinel) {
      final created = await Navigator.of(context).push<Scene>(
        MaterialPageRoute(builder: (_) => const SceneEditorScreen()),
      );
      if (created == null) return;
      ref.read(banksProvider.notifier).setSlot(bank.id, slotIndex, created.id);
      return;
    }
    ref.read(banksProvider.notifier).setSlot(bank.id, slotIndex, chosen.isEmpty ? null : chosen);
  }

  /// Opens the scene sitting in a slot for editing — long-press, so a plain
  /// tap still fires it.
  Future<void> _editSlotScene(Bank bank, int slotIndex) async {
    final sceneId = bank.sceneSlots[slotIndex];
    if (sceneId == null) {
      await _pickScene(bank, slotIndex);
      return;
    }
    final matches = ref.read(scenesProvider).where((s) => s.id == sceneId);
    if (matches.isEmpty) return;
    await Navigator.of(context).push<Scene>(
      MaterialPageRoute(
        builder: (_) => SceneEditorScreen(existing: matches.first, fromBankId: bank.id, fromSlot: slotIndex),
      ),
    );
  }

  void _playSlot(Bank bank, int slotIndex) {
    final sceneId = bank.sceneSlots[slotIndex];
    if (sceneId == null) return;
    final scenes = ref.read(scenesProvider);
    final matches = scenes.where((s) => s.id == sceneId);
    if (matches.isEmpty) return;
    final service = ref.read(artNetServiceProvider);
    if (!service.isConnected) return;
    outputScene(
      service: service,
      scene: matches.first,
      patchedFixtures: ref.read(patchedFixturesProvider),
      universes: ref.read(universesProvider),
    );
    setState(() => _manualSlot = slotIndex);
  }

  /// Deletes a bank, asking first what should happen to its scenes.
  ///
  /// Scenes belong to the project rather than to the bank — a bank only
  /// holds references — so the default is simply to let them go unsorted.
  /// Deleting them is offered, but only for the ones nothing else uses.
  Future<void> _deleteBank(Bank bank) async {
    final inBank = {for (final id in bank.sceneSlots) ?id};
    final usedElsewhere = <String>{
      for (final other in ref.read(banksProvider))
        if (other.id != bank.id)
          for (final id in other.sceneSlots) ?id,
      for (final chase in ref.read(chasesProvider))
        for (final step in chase.steps) ?step.sceneId,
    };
    final exclusive = inBank.difference(usedElsewhere);

    final choice = await askBankDelete(
      context,
      bankName: bank.name,
      sceneCount: inBank.length,
      exclusiveSceneCount: exclusive.length,
    );
    if (choice == BankDeleteChoice.cancel || !mounted) return;

    for (final layer in ref.read(layersProvider)) {
      final current = ref.read(nowPlayingForLayerProvider(layer.id));
      if (current?.kind == PlaybackKind.bank && current?.id == bank.id) {
        stopLayer(ref.read, layer.id);
      }
    }
    if (choice == BankDeleteChoice.deleteScenes) {
      final scenes = ref.read(scenesProvider.notifier);
      for (final id in exclusive) {
        scenes.remove(id);
      }
    }
    ref.read(banksProvider.notifier).remove(bank.id);
    ref.read(selectedBankIdProvider.notifier).state = null;
  }

  Future<void> _renameBank(Bank bank) async {
    final controller = TextEditingController(text: bank.name);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Rename Bank'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (result == true && controller.text.trim().isNotEmpty) {
      ref.read(banksProvider.notifier).rename(bank.id, controller.text.trim());
    }
  }

  Future<void> _resizeBank(Bank bank) async {
    final controller = TextEditingController(text: bank.sceneSlots.length.toString());
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Bank Size'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Number of slots'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    final size = int.tryParse(controller.text);
    if (result == true && size != null && size > 0) {
      ref.read(banksProvider.notifier).resize(bank.id, size);
    }
  }

  @override
  Widget build(BuildContext context) {
    final banks = ref.watch(banksProvider);
    final scenes = ref.watch(scenesProvider);
    if (banks.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Banks'), actions: const [_SceneLibraryAction(), NodeStatusAction(), ControlDockAction(), SaveProjectAction()]),
        body: const Center(child: Text('No banks yet', style: TextStyle(color: AppColors.textFaint))),
      );
    }
    final selectedBankId = ref.watch(selectedBankIdProvider);
    final selected = banks.firstWhere(
      (b) => b.id == selectedBankId,
      orElse: () => banks.first,
    );
    ref.watch(nowPlayingProvider);
    final isRunningThisBank = _isThisBankRunning(selected);
    final runningSlot = ref.watch(layerStepProvider(layer1Id));
    // Watch every other layer's now-playing so this rebuilds when one of
    // them starts/stops this bank, not just when Layer 1 does.
    for (final layer in ref.watch(layersProvider)) {
      if (layer.id != layer1Id) ref.watch(nowPlayingForLayerProvider(layer.id));
    }
    final isRunningThisBankOnAnyOtherLayer = _isThisBankRunningOnAnyOtherLayer(selected);
    final beatSync = ref.watch(beatSyncEnabledProvider);
    final tempo = ref.watch(tempoProvider);
    final autoFade = tempo.autoFade;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Banks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_mosaic_outlined),
            tooltip: 'Scene library',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ScenesScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.file_open_outlined),
            tooltip: 'Import banks / chases',
            onPressed: () async {
              final result = await importShowItemsFromFile(context, ref);
              if (result != null && result.banks.isNotEmpty) {
                ref.read(selectedBankIdProvider.notifier).state = result.banks.first.id;
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'Generate Program',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProgramGeneratorScreen()),
            ),
          ),
          Builder(builder: (context) {
            final onDashboard = ref
                .watch(dashboardTriggersProvider)
                .any((t) => t.id == selected.id && t.kind == TriggerKind.bank);
            return IconButton(
              icon: Icon(onDashboard ? Icons.dashboard : Icons.dashboard_customize_outlined, color: AppColors.accent),
              style: IconButton.styleFrom(
                foregroundColor: AppColors.accent,
                hoverColor: AppColors.accent.withValues(alpha: 0.15),
                highlightColor: AppColors.accent.withValues(alpha: 0.25),
              ),
              tooltip: onDashboard ? 'Remove from Dashboard' : 'Add to Dashboard',
              onPressed: () {
                final notifier = ref.read(dashboardTriggersProvider.notifier);
                notifier.toggle(selected.id, TriggerKind.bank);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      onDashboard
                          ? 'Removed "${selected.name}" from Dashboard'
                          : 'Added "${selected.name}" to Dashboard',
                    ),
                  ),
                );
              },
            );
          }),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename bank',
            onPressed: () => _renameBank(selected),
          ),
          const NodeStatusAction(), const ControlDockAction(), const SaveProjectAction(),
        ],
      ),
      // One scroll for the whole page, scene grid included: with many banks
      // (or a short tablet screen in landscape) the header used to leave
      // the grid a sliver of space that couldn't be scrolled into view.
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.list, size: 16, color: AppColors.accent2),
                      label: Text('All banks (${banks.length})'),
                      tooltip: 'Find a bank by name',
                      onPressed: () => _showAllBanks(banks, selected.id),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: const Text('New'),
                      onPressed: () {
                        final newBank = ref.read(banksProvider.notifier).addBank();
                        _selectBank(newBank.id);
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.flash_on, size: 16, color: AppColors.accent),
                      label: const Text('Beat Flash'),
                      tooltip: 'Every lamp, full, on every beat',
                      onPressed: _addBeatFlashBank,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // At most about two rows of bank chips; more scroll inside
                // this box, so the slots below stay on screen however many
                // banks the show has.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 96),
                  child: Scrollbar(
                    controller: _bankChipsScroll,
                    thumbVisibility: banks.length > 8,
                    child: SingleChildScrollView(
                      controller: _bankChipsScroll,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final bank in banks)
                            ChoiceChip(
                              label: Text(bank.name),
                              visualDensity: VisualDensity.compact,
                              selected: bank.id == selected.id,
                              // Purely navigation: switching which bank's
                              // grid you're looking at must never start,
                              // stop or hand over playback on any layer —
                              // only Run Bank and the layer picker do that.
                              onSelected: (_) => _selectBank(bank.id),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Bank Size: ${selected.sceneSlots.length} slots',
                    style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
                  ),
                ),
                Flexible(
                  flex: 3,
                  child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                Tooltip(
                  message: 'Plays its slots as dark/lit pairs: 1 dark, 2 lit, 3 dark… '
                      'The lit step only stays up for the flash length — on the beat or on the timer.',
                  child: FilterChip(
                    avatar: Icon(Icons.flash_on, size: 14, color: selected.isBeatFlash ? AppColors.accent : AppColors.textFaint),
                    label: const Text('Flash bank'),
                    selected: selected.isBeatFlash,
                    visualDensity: VisualDensity.compact,
                    onSelected: (v) => ref.read(banksProvider.notifier).setBeatFlash(selected.id, v),
                  ),
                ),
                TextButton(onPressed: () => _resizeBank(selected), child: const Text('Edit Size')),
                const SizedBox(width: 4),
                Tooltip(
                  message: 'On: tapping a slot picks its scene and timing instead of playing it',
                  child: FilterChip(
                    avatar: Icon(Icons.edit_note, size: 16, color: _editSlots ? AppColors.accent2 : AppColors.textFaint),
                    label: const Text('Edit slots'),
                    selected: _editSlots,
                    visualDensity: VisualDensity.compact,
                    onSelected: (v) => setState(() => _editSlots = v),
                  ),
                ),
              ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _toggleRun(selected),
                  icon: Icon(isRunningThisBank ? Icons.stop : Icons.play_arrow),
                  label: Text(isRunningThisBank ? 'Stop' : 'Run Bank'),
                ),
                IconButton(
                  onPressed: () => showLayerPickerSheet(context, bank: selected),
                  icon: const Icon(Icons.layers, size: 20),
                  color: isRunningThisBankOnAnyOtherLayer ? AppColors.accent : AppColors.textFaint,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Run on another layer…',
                ),
                const SizedBox(width: 4),
                Tooltip(
                  message: beatSync ? 'Beat Sync on — steps wait for the beat' : 'Beat Sync off — steps on the timer',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.mic_none,
                        size: 16,
                        color: beatSync ? AppColors.accent : AppColors.textFaint,
                      ),
                      Switch(
                        value: beatSync,
                        onChanged: _setBeatSync,
                      ),
                    ],
                  ),
                ),
                if (beatSync && selected.isBeatFlash) ...[
                  const SizedBox(width: 6),
                  const Tooltip(
                    message: 'A Beat Flash bank always flashes on the beat, whatever the app-wide rate',
                    child: Chip(
                      avatar: Icon(Icons.flash_on, size: 14, color: AppColors.accent),
                      label: Text('Flash'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ] else if (beatSync) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Steps per beat',
                    child: SegmentedButton<BeatRate>(
                      segments: [
                        for (final rate in BeatRate.values) ButtonSegment(value: rate, label: Text(rate.label)),
                      ],
                      selected: {ref.watch(beatRateProvider)},
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      // Read live by every running player — no restart.
                      onSelectionChanged: (selection) => ref.read(beatRateProvider.notifier).state = selection.first,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                // What this bank plays at, and the way to change it: its
                // own Hold/Fade, or the dock's when it follows those.
                Expanded(
                  child: InkWell(
                    onTap: () => _editBankTiming(selected.id),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              selected.ownTiming
                                  ? 'Hold ${_seconds(selected.holdMs)} · Fade ${_seconds(selected.fadeMs)} (bank)'
                                  : 'Hold ${tempo.stepSeconds.toStringAsFixed(2)}s · '
                                        'Fade ${tempo.effectiveFadeSeconds.toStringAsFixed(2)}s'
                                        '${autoFade ? ' (auto)' : ''}',
                              style: appMonoStyle(
                                fontSize: 10.5,
                                color: selected.ownTiming ? AppColors.accent : AppColors.textFaint,
                              ),
                            ),
                          ),
                          const Icon(Icons.tune, size: 15, color: AppColors.textFaint),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (selected.isBeatFlash)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  const Tooltip(
                    message: 'How long the lit → dark step takes at the Flash rate. '
                        '0 is a hard cut; a little more gives the flash a short decay.',
                    child: Icon(Icons.timelapse, size: 15, color: AppColors.textFaint),
                  ),
                  const SizedBox(width: 6),
                  const Text('Flash Fade Out', style: TextStyle(fontSize: 11, color: AppColors.textFaint)),
                  Expanded(
                    child: Slider(
                      value: selected.flashFadeOutMs.toDouble().clamp(0, 500),
                      min: 0,
                      max: 500,
                      divisions: 50,
                      label: '${selected.flashFadeOutMs} ms',
                      onChanged: (v) => ref.read(banksProvider.notifier).setFlashFadeOut(selected.id, v.round()),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${selected.flashFadeOutMs}ms',
                      style: appMonoStyle(fontSize: 10.5, color: AppColors.textFaint),
                    ),
                  ),
                ],
              ),
            ),
              ],
            ),
          ),
          Builder(builder: (context) {
              final filledIndices = [
                for (var i = 0; i < selected.sceneSlots.length; i++)
                  if (selected.sceneSlots[i] != null) i,
              ];
              final highlightIndex =
                  (isRunningThisBank && runningSlot != null && runningSlot < filledIndices.length)
                      ? filledIndices[runningSlot]
                      : null;
              return SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 108,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.0,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final sceneId = selected.sceneSlots[index];
                final scene = sceneId == null
                    ? null
                    : scenes.where((s) => s.id == sceneId).firstOrNull;
                // Highlight the step the chase is on while the bank runs, and
                // otherwise the slot the user last fired by hand.
                final isRunning = isRunningThisBank
                    ? index == highlightIndex
                    : scene != null && index == _manualSlot;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    InkWell(
                  borderRadius: BorderRadius.circular(8),
                  // Edit slots mode: the whole tile opens the slot menu, so
                  // nothing fires by accident while the bank is being built.
                  onTap: () => scene == null || _editSlots ? _pickScene(selected, index) : _playSlot(selected, index),
                  // Long-press edits the scene in the slot; the swap menu
                  // moved to the pencil on the tile, so the gesture that
                  // used to just re-pick now does the thing you actually
                  // came for.
                  onLongPress: () => _editSlotScene(selected, index),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isRunning ? AppColors.accent.withValues(alpha: 0.14) : AppColors.panel,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isRunning
                            ? AppColors.accent
                            : _editSlots
                                ? AppColors.accent2.withValues(alpha: 0.6)
                                : AppColors.border,
                        width: 1.5,
                        style: BorderStyle.solid,
                      ),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          scene == null
                              ? Icons.add
                              : _editSlots
                                  ? Icons.swap_horiz
                                  : Icons.play_circle_outline,
                          size: 18,
                          color: scene == null
                              ? AppColors.textFaint
                              : _editSlots
                                  ? AppColors.accent2
                                  : AppColors.accent,
                        ),
                        if (scene != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            scene.name,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, height: 1.15),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        Text('${index + 1}', style: const TextStyle(fontSize: 9, color: AppColors.textFaint)),
                      ],
                    ),
                  ),
                    ),
                    // A step on its own timing shows it; tap to change or reset.
                    if (scene != null && !selected.isBeatFlash && selected.timingAt(index) != null)
                      Positioned(
                        top: 1,
                        left: 1,
                        child: Tooltip(
                          message: 'Own timing: Hold ${_seconds(selected.timingAt(index)!.holdMs)} · '
                              'Fade ${_seconds(selected.timingAt(index)!.fadeMs)}',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(9),
                            onTap: () => _editSlotTiming(selected.id, index),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: AppColors.background.withValues(alpha: 0.75),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.timer_outlined, size: 10, color: AppColors.accent),
                            ),
                          ),
                        ),
                      ),
                    // The slot menu: a corner big enough for a finger (the
                    // whole tile does it in Edit slots mode).
                    if (scene != null && !_editSlots)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Tooltip(
                          message: 'Change scene, step timing…',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _pickScene(selected, index),
                            child: Padding(
                              padding: const EdgeInsets.all(5),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: AppColors.background.withValues(alpha: 0.8),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.edit, size: 14, color: AppColors.textDim),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              }, childCount: selected.sceneSlots.length),
              ),
              );
            }),
          SliverToBoxAdapter(
            child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      final copy = ref.read(banksProvider.notifier).duplicate(selected.id);
                      if (copy != null) ref.read(selectedBankIdProvider.notifier).state = copy.id;
                    },
                    child: const Text('Duplicate Bank'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file, size: 16),
                    label: const Text('Export Bank'),
                    onPressed: () => exportShowItemsToFile(context, ref, bankIds: [selected.id]),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: banks.length <= 1 ? null : () => _deleteBank(selected),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                    child: const Text('Delete Bank'),
                  ),
                ),
              ],
            ),
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// The Scenes list is a second-level screen now, reachable from here.
///
/// Scenes stopped being a top-level tab once slots could create and edit
/// them in place — but a scene that isn't in any bank still has to be
/// findable, so the library stays one tap away.
class _SceneLibraryAction extends StatelessWidget {
  const _SceneLibraryAction();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.auto_awesome_mosaic_outlined),
      tooltip: 'Scene library',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ScenesScreen()),
      ),
    );
  }
}
