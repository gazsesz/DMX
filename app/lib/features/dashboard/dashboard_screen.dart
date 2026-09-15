import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/chase_player.dart';
import '../../core/playback/smart_program_player.dart';
import '../../core/remote/trigger_actions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/control_dock.dart';
import '../../core/widgets/node_status_action.dart';
import '../../core/widgets/save_project_action.dart';
import '../../models/dashboard_prefs.dart';
import '../../models/dashboard_trigger.dart';
import '../../models/smart_program.dart';
import '../../state/artnet_providers.dart';
import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';
import '../../state/control_dock_providers.dart';
import '../../state/dashboard_prefs_providers.dart';
import '../../state/dashboard_providers.dart';
import '../../state/playback_providers.dart';
import '../../state/smart_program_providers.dart';
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
  }

  @override
  void dispose() {
    _smartStatusSub?.cancel();
    super.dispose();
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
    final nowPlaying = ref.watch(nowPlayingProvider);
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
          // Which node is configured, and how many universes — a label, not
          // a status. It used to carry a hardcoded green dot that claimed
          // "connected" whatever the truth was; NodeStatusAction now says
          // that, and having both meant two indicators contradicting each
          // other. Hidden on a phone, where the action row has no room for
          // it and the name is one tap away in Setup anyway.
          if (MediaQuery.sizeOf(context).width >= 600)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Chip(
                backgroundColor: AppColors.panel2,
                side: const BorderSide(color: AppColors.border),
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
          const NodeStatusAction(), const ControlDockAction(), const SaveProjectAction(),
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
              // Skipped when the stage dock is up: it draws the same view
              // right underneath, and two of them stacked is just the
              // Dashboard scrolled twice as far for nothing.
              if (!ref.watch(controlDockProvider).stageVisible) ...[
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
            ],
          ),
        ],
      ),
    );
  }
}
