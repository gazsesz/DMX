import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/chase_player.dart';
import '../../core/playback/smart_program_player.dart';
import '../../core/remote/trigger_actions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/audio/beat_detector.dart';
import '../../core/widgets/beat_meter.dart';
import '../../core/widgets/control_dock.dart';
import '../../core/widgets/save_project_action.dart';
import '../../models/chase.dart';
import '../../models/dashboard_prefs.dart';
import '../../models/dashboard_trigger.dart';
import '../../models/smart_program.dart';
import '../../state/artnet_providers.dart';
import '../../state/audio_providers.dart';
import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';
import '../../state/control_dock_providers.dart';
import '../../state/dashboard_prefs_providers.dart';
import '../../state/dashboard_providers.dart';
import '../../state/playback_providers.dart';
import '../../state/smart_program_providers.dart';
import '../../state/tempo_providers.dart';
import '../fixtures/fixture_layout_screen.dart';
import '../manual_control/manual_control_screen.dart';
import 'live_stage_view.dart';

class _DashboardTrigger {
  final String id;
  final TriggerKind kind;
  final String name;
  final String sub;

  const _DashboardTrigger({required this.id, required this.kind, required this.name, required this.sub});
}

/// What travels with a Dashboard tile while it's being dragged to a new
/// position — [group] keeps the two tile rows from accepting each other's.
class _TileDrag {
  final String group;
  final int index;

  const _TileDrag({required this.group, required this.index});
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final List<DateTime> _taps = [];
  bool _useBpm = false;
  bool _tempoExpanded = true;
  double _sensitivity = 0.6;
  BeatFrequencyBand _frequencyBand = BeatFrequencyBand.overall;
  StreamSubscription<DateTime>? _beatSub;
  late final TextEditingController _bpmController;

  late final ChasePlayer _player;
  late final SmartProgramPlayer _smartPlayer;
  SmartProgramStatus? _smartStatus;
  StreamSubscription<SmartProgramStatus>? _smartStatusSub;

  @override
  void initState() {
    super.initState();
    _player = ref.read(playbackControllerProvider);
    _smartPlayer = ref.read(smartProgramPlayerProvider);
    _smartStatusSub = _smartPlayer.statusStream.listen((status) {
      if (mounted) setState(() => _smartStatus = status);
    });
    _bpmController = TextEditingController(text: ref.read(tempoProvider).bpm.round().toString());
    final beatService = ref.read(beatDetectorProvider);
    _sensitivity = beatService.sensitivity;
    _frequencyBand = beatService.frequencyBand;
    // Always subscribed, but only *acted on* while beat sync is armed: the
    // mic also runs for Smart Programs and for beat-synced chases started
    // elsewhere, and those beats must not quietly drag the tap-tempo (and
    // with it the Step Speed) around behind the user's back.
    _beatSub = beatService.beatEvents.listen((_) {
      if (ref.read(beatSyncEnabledProvider)) _onTap();
    });
  }

  bool get _beatSync => ref.read(beatSyncEnabledProvider);

  @override
  void dispose() {
    _smartStatusSub?.cancel();
    _beatSub?.cancel();
    _bpmController.dispose();
    super.dispose();
  }

  Future<void> _setBeatSync(bool value) async {
    final beatService = ref.read(beatDetectorProvider);
    if (value) {
      beatService.sensitivity = _sensitivity;
      beatService.frequencyBand = _frequencyBand;
    }
    final error = await ref.read(beatSyncEnabledProvider.notifier).setEnabled(value);
    if (error != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
      return;
    }
    await _restartActiveTriggerIfPlaying();
  }

  void _onTap() {
    final now = DateTime.now();
    if (_taps.isNotEmpty && now.difference(_taps.last) > const Duration(seconds: 2)) {
      _taps.clear();
    }
    _taps.add(now);
    if (_taps.length > 5) _taps.removeAt(0);

    if (_taps.length >= 2) {
      final intervals = <int>[];
      for (var i = 1; i < _taps.length; i++) {
        intervals.add(_taps[i].difference(_taps[i - 1]).inMilliseconds);
      }
      final avgMs = intervals.reduce((a, b) => a + b) / intervals.length;
      if (avgMs > 0 && mounted) {
        _setBpm(60000 / avgMs, updateController: true);
      }
    }
  }

  /// Sets tempo from a BPM value, keeping [TempoState.stepSeconds] (what actually
  /// drives bank playback) and the BPM text field in sync with each other
  /// regardless of which one the user is interacting with.
  void _setBpm(double bpm, {required bool updateController}) {
    ref.read(tempoProvider.notifier).setBpm(bpm);
    if (updateController) _bpmController.text = ref.read(tempoProvider).bpm.round().toString();
    // While beat sync is armed the steps are driven by the beats themselves,
    // so a new BPM reading changes nothing about playback — restarting here
    // would kick a running chase back to step 1 on *every single beat*,
    // which is exactly what made a Dashboard-fired bank stutter against the
    // music while the same bank run from the Banks tab kept perfect time.
    if (_beatSync) return;
    _restartActiveTriggerIfPlaying();
  }

  List<_DashboardTrigger> _triggers() {
    final refs = ref.watch(dashboardTriggersProvider);
    final banks = ref.watch(banksProvider);
    final chases = ref.watch(chasesProvider);
    final result = <_DashboardTrigger>[];
    for (final ref_ in refs) {
      if (ref_.kind == TriggerKind.bank) {
        final matches = banks.where((b) => b.id == ref_.id);
        if (matches.isEmpty) continue;
        final bank = matches.first;
        result.add(
          _DashboardTrigger(
            id: bank.id,
            kind: TriggerKind.bank,
            name: bank.name,
            sub: '${bank.sceneSlots.where((s) => s != null).length}/${bank.sceneSlots.length} scenes',
          ),
        );
      } else {
        final matches = chases.where((c) => c.id == ref_.id);
        if (matches.isEmpty) continue;
        final chase = matches.first;
        result.add(
          _DashboardTrigger(
            id: chase.id,
            kind: TriggerKind.chase,
            name: chase.name,
            sub: '${chase.steps.length} steps',
          ),
        );
      }
    }
    return result;
  }

  Future<void> _manageTriggers() async {
    final banks = ref.read(banksProvider);
    final chases = ref.read(chasesProvider);
    if (banks.isEmpty && chases.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a bank or chase first')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.panel,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Consumer(
              builder: (context, sheetRef, _) {
                final selected = sheetRef.watch(dashboardTriggersProvider);
                bool isChecked(String id, TriggerKind kind) =>
                    selected.any((t) => t.id == id && t.kind == kind);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Customize Quick Triggers',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Pick which banks/chases show up on the Dashboard',
                      style: TextStyle(fontSize: 11, color: AppColors.textFaint),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          if (banks.isNotEmpty) ...[
                            const Text(
                              'BANKS',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
                            ),
                            for (final bank in banks)
                              CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: isChecked(bank.id, TriggerKind.bank),
                                onChanged: (_) => sheetRef
                                    .read(dashboardTriggersProvider.notifier)
                                    .toggle(bank.id, TriggerKind.bank),
                                title: Text(bank.name),
                              ),
                          ],
                          if (chases.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'CHASES',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
                            ),
                            for (final chase in chases)
                              CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: isChecked(chase.id, TriggerKind.chase),
                                onChanged: (_) => sheetRef
                                    .read(dashboardTriggersProvider.notifier)
                                    .toggle(chase.id, TriggerKind.chase),
                                title: Text(chase.name),
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Done'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// Both tile taps go through the same shared actions the remote-control
  /// endpoint uses, so a macro fired from a watch does exactly what pressing
  /// the tile here does.
  Future<void> _fireTrigger(_DashboardTrigger trigger) async {
    final message = await togglePlayable(
      ref.read,
      id: trigger.id,
      isBank: trigger.kind == TriggerKind.bank,
      name: trigger.name,
    );
    _reportIfProblem(message);
  }

  Future<void> _toggleSmartProgram(SmartProgram program) async {
    final wasRunning = _smartPlayer.isRunning && _smartPlayer.activeProgramId == program.id;
    final message = await toggleSmartProgramById(ref.read, program.id);
    if (wasRunning && mounted) setState(() => _smartStatus = null);
    _reportIfProblem(message);
  }

  /// The shared actions report what happened; only the failures are worth a
  /// snackbar, since a successful start is obvious from the tile itself.
  void _reportIfProblem(String message) {
    if (!mounted) return;
    if (message.startsWith('Started') || message.startsWith('Stopped')) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Called when the user adjusts the Fade/Hold sliders (or beat sync) while
  /// something is actively playing from the Dashboard — live-applies the new
  /// timing to whatever's running (bank or chase) instead of only affecting
  /// the *next* time it's fired.
  ///
  /// [timingOnly] marks the Hold/Fade sliders as the caller: those don't
  /// touch a chase at all while "Override saved timing" is off, so there's
  /// nothing to re-apply and restarting it from step 1 mid-show would be
  /// pure harm.
  Future<void> _restartActiveTriggerIfPlaying({bool timingOnly = false}) async {
    final current = ref.read(nowPlayingProvider);
    if (!_player.isPlaying || current == null || current.kind == PlaybackKind.smartProgram) return;
    final id = current.id;
    final matches = _triggers().where((t) => t.id == id);
    if (matches.isEmpty) return;
    final trigger = matches.first;

    final Chase chase;
    if (trigger.kind == TriggerKind.bank) {
      chase = bankChase(ref.read, bankId: trigger.id, name: trigger.name);
    } else {
      if (timingOnly && !ref.read(tempoProvider).overrideTiming) return;
      final saved = ref.read(chasesProvider).where((c) => c.id == trigger.id);
      if (saved.isEmpty) return;
      chase = chaseAsDashboardPlaysIt(ref.read, saved.first);
    }
    await startChase(ref.read, chase);
  }

  Future<void> _blackout() async {
    await blackoutEverything(ref.read);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Blackout sent to all universes')));
    }
  }

  Color _kindColor(TriggerKind kind) => kind == TriggerKind.bank ? AppColors.accent2 : AppColors.accent;

  /// A single mosaic tile — used for both Quick Triggers and Smart Programs
  /// so they look and resize identically.
  Widget _buildMosaicTile({
    required DashboardBoxSize boxSize,
    required String kindLabel,
    required String name,
    required String sub,
    required Color color,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.18) : AppColors.panel,
          border: Border.all(color: active ? color : AppColors.border, width: active ? 2 : 1.5),
          borderRadius: BorderRadius.circular(10),
          boxShadow: active ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10)] : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  kindLabel,
                  style: TextStyle(fontSize: boxSize.kindFontSize, fontWeight: FontWeight.w800, color: color),
                ),
                if (active) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.play_arrow, size: boxSize.kindFontSize + 2, color: color),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              name,
              style: TextStyle(
                fontSize: boxSize.nameFontSize,
                fontWeight: FontWeight.w700,
                color: active ? color : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              sub,
              style: TextStyle(
                fontSize: boxSize.subFontSize,
                color: active ? color : AppColors.textFaint,
                fontWeight: active ? FontWeight.w700 : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// A single list row — the list-layout equivalent of [_buildMosaicTile].
  Widget _buildListRow({
    required IconData icon,
    required String name,
    required String sub,
    required Color color,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: active ? color.withValues(alpha: 0.14) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: active ? color : Colors.transparent, width: 1.5),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: color),
        title: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        subtitle: Text(sub, style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint)),
        trailing: Icon(
          active ? Icons.stop_circle : Icons.play_circle_outline,
          color: active ? color : AppColors.textFaint,
        ),
        onTap: onTap,
      ),
    );
  }

  /// Renders a list of tiles in either mosaic or list layout, per the shared
  /// Dashboard tile-size/layout preference.
  /// Wraps a tile so long-pressing drags it and dropping it on another tile
  /// in the *same* group reorders them. The group tag keeps a Quick Trigger
  /// from being dropped into the Smart Programs row and vice versa.
  Widget _reorderableTile({
    required String group,
    required int index,
    required bool mosaic,
    required DashboardBoxSize boxSize,
    required Widget tile,
    required void Function(int from, int to) onReorder,
  }) {
    final dragged = LongPressDraggable<_TileDrag>(
      data: _TileDrag(group: group, index: index),
      feedback: Material(
        type: MaterialType.transparency,
        child: Opacity(
          opacity: 0.9,
          child: SizedBox(
            width: mosaic ? boxSize.extent : 260,
            height: mosaic ? boxSize.extent : 64,
            child: tile,
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: tile),
      child: tile,
    );
    return DragTarget<_TileDrag>(
      onWillAcceptWithDetails: (details) => details.data.group == group && details.data.index != index,
      onAcceptWithDetails: (details) => onReorder(details.data.index, index),
      builder: (context, candidate, rejected) {
        if (candidate.isEmpty) return dragged;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.accent2, width: 2),
          ),
          child: dragged,
        );
      },
    );
  }

  Widget _buildTileGroup({
    required TriggerLayout layout,
    required DashboardBoxSize boxSize,
    required List<Widget Function(bool mosaic)> tileBuilders,
    required String group,
    required void Function(int from, int to) onReorder,
  }) {
    Widget tileAt(int index, bool mosaic) => _reorderableTile(
      group: group,
      index: index,
      mosaic: mosaic,
      boxSize: boxSize,
      tile: tileBuilders[index](mosaic),
      onReorder: onReorder,
    );

    if (layout == TriggerLayout.mosaic) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: tileBuilders.length,
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: boxSize.extent,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.0,
        ),
        itemBuilder: (context, index) => tileAt(index, true),
      );
    }
    return Column(children: [for (var i = 0; i < tileBuilders.length; i++) tileAt(i, false)]);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(artNetSettingsProvider);
    final universes = ref.watch(universesProvider);
    final dashPrefs = ref.watch(dashboardPrefsProvider);
    final layout = dashPrefs.layout;
    final boxSize = dashPrefs.boxSize;
    void setLayout(TriggerLayout value) {
      ref.read(dashboardPrefsProvider.notifier).update((p) => DashboardPrefsState(layout: value, boxSize: p.boxSize));
    }

    void setBoxSize(DashboardBoxSize value) {
      ref.read(dashboardPrefsProvider.notifier).update((p) => DashboardPrefsState(layout: p.layout, boxSize: value));
    }

    final triggers = _triggers();
    final smartPrograms = ref.watch(smartProgramsProvider);
    final smartActive = _smartPlayer.isRunning;
    final beatSync = ref.watch(beatSyncEnabledProvider);
    final nowPlaying = ref.watch(nowPlayingProvider);
    final tempo = ref.watch(tempoProvider);
    // Derived straight from the shared NowPlaying state — not a local flag —
    // so a trigger fired from the Banks or Chase tab shows as active here
    // too, and vice versa.
    final activeTriggerId = (_player.isPlaying && nowPlaying?.kind != PlaybackKind.smartProgram)
        ? nowPlaying?.id
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Chip(
              backgroundColor: AppColors.panel2,
              side: const BorderSide(color: AppColors.border),
              avatar: const Icon(Icons.circle, size: 8, color: AppColors.success),
              label: Text(
                '${settings.deviceName} · ${universes.length}U',
                style: const TextStyle(fontSize: 11, color: AppColors.textDim),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Manual Control',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ManualControlScreen()),
            ),
          ),
          const ControlDockAction(), const SaveProjectAction(),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'QUICK TRIGGERS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: AppColors.textFaint,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Add / remove triggers',
                        icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.textFaint),
                        onPressed: _manageTriggers,
                      ),
                      if (layout == TriggerLayout.mosaic)
                        PopupMenuButton<DashboardBoxSize>(
                          tooltip: 'Box size',
                          initialValue: boxSize,
                          onSelected: setBoxSize,
                          color: AppColors.panel2,
                          itemBuilder: (context) => [
                            for (final size in DashboardBoxSize.values)
                              PopupMenuItem(value: size, child: Text(size.label)),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.photo_size_select_large_outlined, size: 16, color: AppColors.textFaint),
                                const SizedBox(width: 3),
                                Text(boxSize.label, style: appMonoStyle(fontSize: 10.5, color: AppColors.textFaint)),
                              ],
                            ),
                          ),
                        ),
                      IconButton(
                        tooltip: 'Mosaic view',
                        icon: Icon(
                          Icons.grid_view,
                          size: 18,
                          color: layout == TriggerLayout.mosaic ? AppColors.accent : AppColors.textFaint,
                        ),
                        onPressed: () => setLayout(TriggerLayout.mosaic),
                      ),
                      IconButton(
                        tooltip: 'List view',
                        icon: Icon(
                          Icons.view_list,
                          size: 18,
                          color: layout == TriggerLayout.list ? AppColors.accent : AppColors.textFaint,
                        ),
                        onPressed: () => setLayout(TriggerLayout.list),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (triggers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    ref.watch(banksProvider).isEmpty && ref.watch(chasesProvider).isEmpty
                        ? 'No banks or chases yet — create some in the Bank/Chase tabs'
                        : 'No triggers yet — tap the pencil to add some',
                    style: const TextStyle(color: AppColors.textFaint),
                  ),
                )
              else
                _buildTileGroup(
                  layout: layout,
                  boxSize: boxSize,
                  group: 'trigger',
                  onReorder: (from, to) => ref.read(dashboardTriggersProvider.notifier).move(from, to),
                  tileBuilders: [
                    for (final trigger in triggers)
                      (mosaic) {
                        final active = activeTriggerId == trigger.id;
                        final color = _kindColor(trigger.kind);
                        final name = trigger.kind == TriggerKind.bank ? 'BANK' : 'CHASE';
                        return mosaic
                            ? _buildMosaicTile(
                                boxSize: boxSize,
                                kindLabel: name,
                                name: trigger.name,
                                sub: trigger.sub,
                                color: color,
                                active: active,
                                onTap: () => _fireTrigger(trigger),
                              )
                            : _buildListRow(
                                icon: trigger.kind == TriggerKind.bank
                                    ? Icons.grid_view_outlined
                                    : Icons.fast_forward_outlined,
                                name: trigger.name,
                                sub: trigger.sub,
                                color: color,
                                active: active,
                                onTap: () => _fireTrigger(trigger),
                              );
                      },
                  ],
                ),
              const SizedBox(height: 22),
              const Text(
                'SMART PROGRAMS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: AppColors.textFaint,
                ),
              ),
              const Text(
                'Switches chases automatically as the live music tempo changes',
                style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
              ),
              const SizedBox(height: 8),
              if (smartPrograms.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'None yet — create one from the Chase tab',
                    style: TextStyle(color: AppColors.textFaint, fontSize: 12),
                  ),
                )
              else
                _buildTileGroup(
                  layout: layout,
                  boxSize: boxSize,
                  group: 'smart',
                  onReorder: (from, to) => ref.read(smartProgramsProvider.notifier).move(from, to),
                  tileBuilders: [
                    for (final program in smartPrograms)
                      (mosaic) {
                        final active = _smartPlayer.isRunning && _smartPlayer.activeProgramId == program.id;
                        final status = active ? _smartStatus : null;
                        final zoneLabel = status?.isSilent == true
                            ? 'No music'
                            : switch (status?.zone) {
                                SmartProgramZone.faster => 'Faster',
                                SmartProgramZone.slower => 'Slower',
                                _ => 'Base',
                              };
                        final sub = active
                            ? '$zoneLabel${status?.liveBpm != null ? ' · ${status!.liveBpm!.round()} BPM' : ''}'
                            : '${program.baseBpm.round()} BPM base';
                        return mosaic
                            ? _buildMosaicTile(
                                boxSize: boxSize,
                                kindLabel: 'SMART',
                                name: program.name,
                                sub: sub,
                                color: AppColors.accent2,
                                active: active,
                                onTap: () => _toggleSmartProgram(program),
                              )
                            : _buildListRow(
                                icon: Icons.auto_graph,
                                name: program.name,
                                sub: sub,
                                color: AppColors.accent2,
                                active: active,
                                onTap: () => _toggleSmartProgram(program),
                              );
                      },
                  ],
                ),
              const SizedBox(height: 22),
              InkWell(
                onTap: () => setState(() => _tempoExpanded = !_tempoExpanded),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TEMPO & CHASE SPEED',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: AppColors.textFaint,
                      ),
                    ),
                    Icon(
                      _tempoExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: AppColors.textFaint,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (_tempoExpanded)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          OutlinedButton(
                            onPressed: _onTap,
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              side: const BorderSide(color: AppColors.accent, width: 1.5),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  'TAP',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.accent,
                                    letterSpacing: 1,
                                  ),
                                ),
                                Text(tempo.bpm.round().toString(), style: appMonoStyle(fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        smartActive
                                            ? 'Step Speed (Smart Program active)'
                                            : beatSync
                                                ? 'Step Speed (synced to beat)'
                                                : tempo.overrideTiming
                                                    ? 'Step Speed (Bank + Chase triggers)'
                                                    : 'Step Speed (Bank triggers)',
                                        style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
                                      ),
                                    ),
                                    if (!beatSync && !smartActive)
                                      SegmentedButton<bool>(
                                        segments: const [
                                          ButtonSegment(value: false, label: Text('Sec')),
                                          ButtonSegment(value: true, label: Text('BPM')),
                                        ],
                                        selected: {_useBpm},
                                        showSelectedIcon: false,
                                        style: const ButtonStyle(
                                          visualDensity: VisualDensity.compact,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        onSelectionChanged: (s) => setState(() => _useBpm = s.first),
                                      ),
                                  ],
                                ),
                                if (_useBpm && !beatSync && !smartActive) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                                        onPressed: () => _setBpm(tempo.bpm - 1, updateController: true),
                                      ),
                                      Expanded(
                                        child: TextField(
                                          controller: _bpmController,
                                          textAlign: TextAlign.center,
                                          keyboardType: TextInputType.number,
                                          style: appMonoStyle(fontWeight: FontWeight.w700),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            suffixText: 'BPM',
                                          ),
                                          onChanged: (text) {
                                            final value = double.tryParse(text);
                                            if (value != null) _setBpm(value, updateController: false);
                                          },
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline, size: 20),
                                        onPressed: () => _setBpm(tempo.bpm + 1, updateController: true),
                                      ),
                                    ],
                                  ),
                                ] else ...[
                                  Slider(
                                    value: tempo.stepSeconds,
                                    min: 0.0,
                                    max: 5,
                                    onChanged: (beatSync || smartActive)
                                        ? null
                                        : (value) => ref.read(tempoProvider.notifier).setStepSeconds(value),
                                    onChangeEnd: (beatSync || smartActive)
                                        ? null
                                        : (_) => _restartActiveTriggerIfPlaying(timingOnly: true),
                                  ),
                                ],
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    '${tempo.stepSeconds.toStringAsFixed(2)}s / step · ${(60 / tempo.stepSeconds).clamp(0, 999).toStringAsFixed(0)} BPM',
                                    style: appMonoStyle(fontSize: 11, color: AppColors.textDim),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        smartActive
                            ? 'Fade Time (set on the Smart Program)'
                            : tempo.overrideTiming
                                ? 'Fade Time (Bank + Chase triggers)'
                                : 'Fade Time (Bank triggers)',
                        style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
                      ),
                      Slider(
                        value: tempo.fadeSeconds,
                        min: 0.0,
                        max: 5,
                        activeColor: AppColors.accent2,
                        onChanged: smartActive ? null : (value) => ref.read(tempoProvider.notifier).setFadeSeconds(value),
                        onChangeEnd: smartActive ? null : (_) => _restartActiveTriggerIfPlaying(timingOnly: true),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${tempo.fadeSeconds.toStringAsFixed(2)}s fade',
                          style: appMonoStyle(fontSize: 11, color: AppColors.textDim),
                        ),
                      ),
                      const Divider(height: 26),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Override saved timing',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  tempo.overrideTiming
                                      ? 'Chases run at the Hold/Fade set here, not their own'
                                      : 'Chases keep their own per-step timing (banks always follow this)',
                                  style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: tempo.overrideTiming,
                            onChanged: smartActive
                                ? null
                                : (value) {
                                    ref.read(tempoProvider.notifier).setOverrideTiming(value);
                                    _restartActiveTriggerIfPlaying();
                                  },
                          ),
                        ],
                      ),
                      const Divider(height: 26),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.mic_none, size: 18, color: AppColors.textDim),
                              SizedBox(width: 8),
                              Text('Beat Sync (Mic)', style: TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                          Switch(
                            value: beatSync,
                            onChanged: (value) => _setBeatSync(value),
                          ),
                        ],
                      ),
                      if (beatSync)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text(
                                'Beat Rate — steps per beat',
                                style: TextStyle(fontSize: 12, color: AppColors.textDim),
                              ),
                            ),
                            SegmentedButton<BeatRate>(
                              segments: [
                                for (final rate in BeatRate.values)
                                  ButtonSegment(value: rate, label: Text(rate.label)),
                              ],
                              selected: {ref.watch(beatRateProvider)},
                              showSelectedIcon: false,
                              style: const ButtonStyle(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onSelectionChanged: (selection) {
                                ref.read(beatRateProvider.notifier).state = selection.first;
                                _restartActiveTriggerIfPlaying();
                              },
                            ),
                          ],
                        ),
                      if (beatSync) ...[
                        const SizedBox(height: 10),
                        BeatMeter(service: ref.read(beatDetectorProvider)),
                        const SizedBox(height: 10),
                        const Text(
                          'Sensitivity',
                          style: TextStyle(fontSize: 11, color: AppColors.textFaint),
                        ),
                        Slider(
                          value: _sensitivity,
                          activeColor: AppColors.accent2,
                          onChanged: (value) {
                            setState(() => _sensitivity = value);
                            ref.read(beatDetectorProvider).sensitivity = value;
                          },
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'React to',
                          style: TextStyle(fontSize: 11, color: AppColors.textFaint),
                        ),
                        const SizedBox(height: 6),
                        SegmentedButton<BeatFrequencyBand>(
                          segments: [
                            for (final band in BeatFrequencyBand.values)
                              ButtonSegment(value: band, label: Text(band.label)),
                          ],
                          selected: {_frequencyBand},
                          onSelectionChanged: (selection) {
                            setState(() => _frequencyBand = selection.first);
                            ref.read(beatDetectorProvider).frequencyBand = selection.first;
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'LIVE STAGE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: AppColors.textFaint,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit stage layout',
                    icon: const Icon(Icons.open_in_full, size: 16, color: AppColors.textFaint),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const FixtureLayoutScreen()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const SizedBox(height: 220, child: LiveStageView()),
            ],
          ),
          // The control dock carries its own Blackout, so two of them on
          // screen would just be a bigger target for the wrong one.
          if (!ref.watch(controlDockProvider).visible)
            Positioned(
              right: 16,
              bottom: 24,
              child: FloatingActionButton(
                backgroundColor: AppColors.danger,
                onPressed: _blackout,
                child: const Icon(Icons.power_settings_new, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
