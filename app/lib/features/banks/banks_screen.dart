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
import '../../core/widgets/node_status_action.dart';
import '../../core/widgets/save_project_action.dart';
import '../../models/bank.dart';
import '../../models/chase.dart';
import '../../models/dashboard_trigger.dart';
import '../../models/scene.dart';
import '../../state/artnet_providers.dart';
import '../../state/audio_providers.dart';
import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';
import '../../state/control_dock_providers.dart';
import '../../state/dashboard_providers.dart';
import '../../state/fixture_providers.dart';
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
  String? _selectedBankId;
  late final ChasePlayer _player;
  int? _runningSlot;

  /// The slot the user last fired by hand — so tapping a scene shows which
  /// one is live even when the bank isn't running as a chase.
  int? _manualSlot;

  @override
  void initState() {
    super.initState();
    _player = ref.read(playbackControllerProvider);
  }

  bool _isThisBankRunning(Bank bank) {
    final current = ref.read(nowPlayingProvider);
    return _player.isPlaying && current?.kind == PlaybackKind.bank && current?.id == bank.id;
  }

  void _toggleRun(Bank bank) {
    if (_isThisBankRunning(bank)) {
      _player.stop();
      ref.read(nowPlayingProvider.notifier).state = null;
      setState(() => _runningSlot = null);
      return;
    }
    final service = ref.read(artNetServiceProvider);
    if (!service.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected — check Settings')),
      );
      return;
    }
    ref.read(smartProgramPlayerProvider).stop();
    final beatSync = ref.read(beatSyncEnabledProvider);
    // One set of timing for the whole app — this screen's own Hold/Fade
    // sliders are gone, and the dock's panel is where they live now.
    final tempo = ref.read(tempoProvider);
    final chase = Chase(
      id: 'bank-run-${bank.id}',
      name: bank.name,
      steps: [
        ChaseStep(
          bankId: bank.id,
          hold: tempo.hold,
          fade: tempo.fade,
        ),
      ],
      direction: ChaseDirection.forward,
      beatSync: beatSync,
    );
    _player.play(
      chase: chase,
      scenes: ref.read(scenesProvider),
      banks: ref.read(banksProvider),
      patchedFixtures: ref.read(patchedFixturesProvider),
      universes: ref.read(universesProvider),
      service: service,
      beatStream: beatSync ? ref.read(beatPredictorProvider).events : null,
      beatRate: beatRateOf(ref),
      flashLength: ref.read(flashLengthProvider),
      liveBeatRate: () => ref.read(beatRateProvider),
      liveFlashLength: () => ref.read(flashLengthProvider),
      // Auto-fade is app-wide, so it governs a bank run from here too. It
      // used to be ignored on this screen, which made the local Fade
      // slider look like it was beating auto-fade in a fight.
      fadeOverride: () {
        final tempo = ref.read(tempoProvider);
        return tempo.autoFade ? tempo.fade : null;
      },
      onStep: (index) {
        if (mounted) setState(() => _runningSlot = index);
      },
    );
    ref.read(nowPlayingProvider.notifier).state = NowPlaying(
      id: bank.id,
      kind: PlaybackKind.bank,
      name: bank.name,
    );
    setState(() => _manualSlot = null);
  }

  Future<void> _setBeatSync(bool value) async {
    final error = await ref.read(beatSyncEnabledProvider.notifier).setEnabled(value);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    // Re-arm whatever is running so it picks up (or drops) beat stepping
    // right away instead of only on the next run.
    final banks = ref.read(banksProvider);
    final running = banks.where(_isThisBankRunning);
    if (running.isNotEmpty) {
      final bank = running.first;
      _player.stop();
      _toggleRun(bank);
    }
  }

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
  Future<void> _addBeatFlashBank() async {
    final fixtures = ref.read(patchedFixturesProvider);
    if (fixtures.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No patched fixtures — patch your lamps first')),
      );
      return;
    }

    final color = await showColorPickerDialog(context, initial: const [255, 255, 255]);
    if (!mounted) return;

    final scenes = buildBeatFlashScenes(
      fixtures: fixtures,
      idGenerator: () => _uuid.v4(),
      color: color ?? const [255, 255, 255],
    );
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
    final bank = banksNotifier.addBank(name: name, slots: scenes.length, isBeatFlash: true);
    for (var i = 0; i < scenes.length; i++) {
      banksNotifier.setSlot(bank.id, i, scenes[i].id);
    }

    ref.read(beatRateProvider.notifier).state = BeatRate.flash;
    setState(() {
      _selectedBankId = bank.id;
      _runningSlot = null;
      _manualSlot = null;
    });
    // Arms the mic through the same path as the switch below, so a denied
    // or busy microphone reports itself the way it does everywhere else.
    await _setBeatSync(true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"$name" ready — hit Run Bank and it flashes on every beat')),
    );
  }

  void _restartRunIfPlaying(Bank bank) {
    if (!_isThisBankRunning(bank)) return;
    _player.stop();
    _toggleRun(bank);
  }

  static const _newSceneSentinel = '__new__';

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
      MaterialPageRoute(builder: (_) => SceneEditorScreen(existing: matches.first)),
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

    if (_isThisBankRunning(bank)) {
      _player.stop();
      ref.read(nowPlayingProvider.notifier).state = null;
    }
    if (choice == BankDeleteChoice.deleteScenes) {
      final scenes = ref.read(scenesProvider.notifier);
      for (final id in exclusive) {
        scenes.remove(id);
      }
    }
    ref.read(banksProvider.notifier).remove(bank.id);
    setState(() => _selectedBankId = null);
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
    final selected = banks.firstWhere(
      (b) => b.id == _selectedBankId,
      orElse: () => banks.first,
    );
    final nowPlaying = ref.watch(nowPlayingProvider);
    final isRunningThisBank =
        _player.isPlaying && nowPlaying?.kind == PlaybackKind.bank && nowPlaying?.id == selected.id;
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
      body: Column(
        children: [
          Padding(
            // Wraps rather than scrolling sideways: once a show has a dozen
            // banks the ones past the edge are invisible, and a horizontal
            // strip inside a vertically scrolling page is awkward to reach
            // for anyway. No fixed height — the rows have to be free to
            // stack.
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final bank in banks)
                  Padding(
                    padding: EdgeInsets.zero,
                    child: ChoiceChip(
                      label: Text(bank.name),
                      selected: bank.id == selected.id,
                      onSelected: (_) {
                        // Hand playback over rather than dropping it: if
                        // the bank you're leaving was running, the one you
                        // switch to picks up and keeps going. Switching
                        // banks mid-show is a transition, not a stop.
                        final wasRunning = _isThisBankRunning(selected);
                        if (wasRunning) {
                          _player.stop();
                          ref.read(nowPlayingProvider.notifier).state = null;
                        }
                        setState(() {
                          _selectedBankId = bank.id;
                          _runningSlot = null;
                          _manualSlot = null;
                        });
                        if (wasRunning) _toggleRun(bank);
                      },
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('New'),
                  onPressed: () {
                    final newBank = ref.read(banksProvider.notifier).addBank();
                    setState(() => _selectedBankId = newBank.id);
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
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Bank Size: ${selected.sceneSlots.length} slots',
                  style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
                ),
                TextButton(onPressed: () => _resizeBank(selected), child: const Text('Edit Size')),
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
                const SizedBox(width: 8),
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
                if (beatSync) ...[
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
                      onSelectionChanged: (selection) {
                        ref.read(beatRateProvider.notifier).state = selection.first;
                        _restartRunIfPlaying(selected);
                      },
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                // A readout, not a control. This screen used to carry its
                // own Hold/Fade sliders that quietly disagreed with the
                // Dashboard's — which is how auto-fade ended up looking
                // like it was losing a fight with a slider. One set of
                // timing now, in the dock's panel, and this says what it
                // currently is and where to change it.
                Expanded(
                  child: InkWell(
                    onTap: () => ref.read(controlDockProvider.notifier).toggleExpanded(),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Hold ${tempo.stepSeconds.toStringAsFixed(2)}s · '
                              'Fade ${tempo.effectiveFadeSeconds.toStringAsFixed(2)}s'
                              '${autoFade ? ' (auto)' : ''}',
                              style: appMonoStyle(fontSize: 10.5, color: AppColors.textFaint),
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
          Expanded(
            child: Builder(builder: (context) {
              final filledIndices = [
                for (var i = 0; i < selected.sceneSlots.length; i++)
                  if (selected.sceneSlots[i] != null) i,
              ];
              final highlightIndex =
                  (isRunningThisBank && _runningSlot != null && _runningSlot! < filledIndices.length)
                      ? filledIndices[_runningSlot!]
                      : null;
              return GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              itemCount: selected.sceneSlots.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 76,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.0,
              ),
              itemBuilder: (context, index) {
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
                  children: [
                    InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => scene == null ? _pickScene(selected, index) : _playSlot(selected, index),
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
                        color: isRunning ? AppColors.accent : AppColors.border,
                        width: 1.5,
                        style: BorderStyle.solid,
                      ),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          scene == null ? Icons.add : Icons.play_circle_outline,
                          size: 13,
                          color: scene == null ? AppColors.textFaint : AppColors.accent,
                        ),
                        if (scene != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            scene.name,
                            style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        Text('${index + 1}', style: const TextStyle(fontSize: 7, color: AppColors.textFaint)),
                      ],
                    ),
                  ),
                    ),
                    if (scene != null)
                      Positioned(
                        top: 1,
                        right: 1,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(9),
                          onTap: () => _pickScene(selected, index),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: AppColors.background.withValues(alpha: 0.75),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.edit, size: 10, color: AppColors.textDim),
                          ),
                        ),
                      ),
                  ],
                );
              },
              );
            }),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => ref.read(banksProvider.notifier).duplicate(selected.id),
                    child: const Text('Duplicate Bank'),
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
