import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/chase_player.dart';
import '../../core/playback/smart_program_player.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/audio/beat_detector.dart';
import '../../core/widgets/beat_meter.dart';
import '../../core/widgets/save_project_action.dart';
import '../../models/chase.dart';
import '../../models/dashboard_prefs.dart';
import '../../models/dashboard_trigger.dart';
import '../../models/smart_program.dart';
import '../../state/artnet_providers.dart';
import '../../state/audio_providers.dart';
import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';
import '../../state/dashboard_prefs_providers.dart';
import '../../state/dashboard_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/playback_providers.dart';
import '../../state/scene_providers.dart';
import '../../state/smart_program_providers.dart';
import '../chases/smart_program_editor_screen.dart';
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

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final List<DateTime> _taps = [];
  double _bpm = 120;
  double _stepSeconds = 1.2;
  double _fadeSeconds = 0.3;
  bool _useBpm = false;
  bool _beatSync = false;
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
    _bpmController = TextEditingController(text: _bpm.round().toString());
    final beatService = ref.read(beatDetectorProvider);
    _sensitivity = beatService.sensitivity;
    _frequencyBand = beatService.frequencyBand;
    _beatSync = beatService.isListening;
    if (_beatSync) {
      _beatSub = beatService.beatEvents.listen((_) => _onTap());
    }
  }

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
      final started = await beatService.start();
      if (!started) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(beatService.lastError ?? 'Could not start the microphone')),
          );
        }
        return;
      }
      beatService.sensitivity = _sensitivity;
      beatService.frequencyBand = _frequencyBand;
      _beatSub = beatService.beatEvents.listen((_) => _onTap());
    } else {
      await beatService.stop();
      await _beatSub?.cancel();
      _beatSub = null;
    }
    if (mounted) setState(() => _beatSync = value);
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

  /// Sets tempo from a BPM value, keeping [_stepSeconds] (what actually
  /// drives bank playback) and the BPM text field in sync with each other
  /// regardless of which one the user is interacting with.
  void _setBpm(double bpm, {required bool updateController}) {
    final clamped = bpm.clamp(20.0, 300.0);
    setState(() {
      _bpm = clamped;
      _stepSeconds = (60 / clamped).clamp(0.0, 5.0);
    });
    if (updateController) _bpmController.text = clamped.round().toString();
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

  Future<void> _fireTrigger(_DashboardTrigger trigger) async {
    final current = ref.read(nowPlayingProvider);
    final isThisActive = _player.isPlaying && current?.id == trigger.id && current?.kind != PlaybackKind.smartProgram;
    if (isThisActive) {
      _player.stop();
      ref.read(nowPlayingProvider.notifier).state = null;
      return;
    }
    final service = ref.read(artNetServiceProvider);
    if (!service.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected — check Settings')),
      );
      return;
    }

    Chase chase;
    if (trigger.kind == TriggerKind.bank) {
      chase = Chase(
        id: 'dashboard-bank-${trigger.id}',
        name: trigger.name,
        steps: [
          ChaseStep(
            bankId: trigger.id,
            hold: Duration(milliseconds: (_stepSeconds * 1000).round()),
            fade: Duration(milliseconds: (_fadeSeconds * 1000).round()),
          ),
        ],
        beatSync: _beatSync,
      );
    } else {
      // Play the chase with its own configured timing the first time it's
      // fired — Dashboard's Fade/Hold sliders only take over live if the
      // user actually touches them while it's running (see
      // `_restartActiveTriggerIfPlaying`), so a saved chase's own per-step
      // timing isn't silently clobbered by Dashboard's defaults.
      final matches = ref.read(chasesProvider).where((c) => c.id == trigger.id);
      if (matches.isEmpty) return;
      chase = matches.first;
    }

    await _startChase(chase);
    ref.read(nowPlayingProvider.notifier).state = NowPlaying(
      id: trigger.id,
      kind: trigger.kind == TriggerKind.bank ? PlaybackKind.bank : PlaybackKind.chase,
      name: trigger.name,
    );
  }

  Future<void> _toggleSmartProgram(SmartProgram program) async {
    if (_smartPlayer.isRunning && _smartPlayer.activeProgramId == program.id) {
      _smartPlayer.stop();
      setState(() => _smartStatus = null);
      ref.read(nowPlayingProvider.notifier).state = null;
      return;
    }
    final service = ref.read(artNetServiceProvider);
    if (!service.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected — check Settings')),
      );
      return;
    }
    if (program.baseChaseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set a base chase for this program first — edit it on the Chase tab')),
      );
      return;
    }
    _player.stop();
    ref.read(nowPlayingProvider.notifier).state = null;
    final started = await _smartPlayer.start(
      program: program,
      chases: ref.read(chasesProvider),
      scenes: ref.read(scenesProvider),
      banks: ref.read(banksProvider),
      patchedFixtures: ref.read(patchedFixturesProvider),
      universes: ref.read(universesProvider),
      service: service,
    );
    if (started) {
      ref.read(nowPlayingProvider.notifier).state = NowPlaying(
        id: program.id,
        kind: PlaybackKind.smartProgram,
        name: program.name,
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start the microphone for tempo tracking')),
      );
    }
  }

  Future<void> _startChase(Chase chase) async {
    ref.read(smartProgramPlayerProvider).stop();
    final service = ref.read(artNetServiceProvider);
    Stream<DateTime>? beatStream;
    if (chase.beatSync) {
      final beatService = ref.read(beatDetectorProvider);
      final started = await beatService.start();
      if (started) beatStream = beatService.beatEvents;
    }
    _player.play(
      chase: chase,
      scenes: ref.read(scenesProvider),
      banks: ref.read(banksProvider),
      patchedFixtures: ref.read(patchedFixturesProvider),
      universes: ref.read(universesProvider),
      service: service,
      beatStream: beatStream,
      onStep: (_) {},
    );
  }

  /// Called when the user adjusts the Fade/Hold sliders (or beat sync) while
  /// something is actively playing from the Dashboard — live-applies the new
  /// timing to whatever's running (bank or chase) instead of only affecting
  /// the *next* time it's fired.
  Future<void> _restartActiveTriggerIfPlaying() async {
    final current = ref.read(nowPlayingProvider);
    if (!_player.isPlaying || current == null || current.kind == PlaybackKind.smartProgram) return;
    final id = current.id;
    final matches = _triggers().where((t) => t.id == id);
    if (matches.isEmpty) return;
    final trigger = matches.first;

    final hold = Duration(milliseconds: (_stepSeconds * 1000).round());
    final fade = Duration(milliseconds: (_fadeSeconds * 1000).round());
    Chase chase;
    if (trigger.kind == TriggerKind.bank) {
      chase = Chase(
        id: 'dashboard-bank-${trigger.id}',
        name: trigger.name,
        steps: [ChaseStep(bankId: trigger.id, hold: hold, fade: fade)],
        beatSync: _beatSync,
      );
    } else {
      final matches = ref.read(chasesProvider).where((c) => c.id == trigger.id);
      if (matches.isEmpty) return;
      final saved = matches.first;
      chase = saved.copyWith(
        beatSync: _beatSync,
        steps: [
          for (final step in saved.steps)
            ChaseStep(sceneId: step.sceneId, bankId: step.bankId, hold: hold, fade: fade),
        ],
      );
    }
    await _startChase(chase);
  }

  Future<void> _blackout() async {
    _player.stop();
    ref.read(smartProgramPlayerProvider).stop();
    final service = ref.read(artNetServiceProvider);
    if (!service.isConnected) {
      await service.connect(ref.read(artNetSettingsProvider));
    }
    service.blackoutAll(ref.read(universesProvider));
    ref.read(nowPlayingProvider.notifier).state = null;
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
              style: TextStyle(fontSize: boxSize.nameFontSize, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              sub,
              style: TextStyle(fontSize: boxSize.subFontSize, color: AppColors.textFaint),
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
  Widget _buildTileGroup({
    required TriggerLayout layout,
    required DashboardBoxSize boxSize,
    required List<Widget Function(bool mosaic)> tileBuilders,
  }) {
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
        itemBuilder: (context, index) => tileBuilders[index](true),
      );
    }
    return Column(children: [for (final builder in tileBuilders) builder(false)]);
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
          const SaveProjectAction(),
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
                  tileBuilders: [
                    for (final program in smartPrograms)
                      (mosaic) {
                        final active = _smartPlayer.isRunning && _smartPlayer.activeProgramId == program.id;
                        final status = active ? _smartStatus : null;
                        final zoneLabel = switch (status?.zone) {
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
                                Text(_bpm.round().toString(), style: appMonoStyle(fontWeight: FontWeight.w700)),
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
                                            : _beatSync
                                                ? 'Step Speed (synced to beat)'
                                                : 'Step Speed (Bank triggers)',
                                        style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
                                      ),
                                    ),
                                    if (!_beatSync && !smartActive)
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
                                if (_useBpm && !_beatSync && !smartActive) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                                        onPressed: () => _setBpm(_bpm - 1, updateController: true),
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
                                        onPressed: () => _setBpm(_bpm + 1, updateController: true),
                                      ),
                                    ],
                                  ),
                                ] else ...[
                                  Slider(
                                    value: _stepSeconds,
                                    min: 0.0,
                                    max: 5,
                                    onChanged: (_beatSync || smartActive)
                                        ? null
                                        : (value) => setState(() => _stepSeconds = value),
                                    onChangeEnd: (_beatSync || smartActive) ? null : (_) => _restartActiveTriggerIfPlaying(),
                                  ),
                                ],
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    '${_stepSeconds.toStringAsFixed(2)}s / step · ${(60 / _stepSeconds).clamp(0, 999).toStringAsFixed(0)} BPM',
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
                        smartActive ? 'Fade Time (set on the Smart Program)' : 'Fade Time (Bank/Chase triggers)',
                        style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
                      ),
                      Slider(
                        value: _fadeSeconds,
                        min: 0.0,
                        max: 5,
                        activeColor: AppColors.accent2,
                        onChanged: smartActive ? null : (value) => setState(() => _fadeSeconds = value),
                        onChangeEnd: smartActive ? null : (_) => _restartActiveTriggerIfPlaying(),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${_fadeSeconds.toStringAsFixed(2)}s fade',
                          style: appMonoStyle(fontSize: 11, color: AppColors.textDim),
                        ),
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
                            value: _beatSync,
                            onChanged: (value) => _setBeatSync(value),
                          ),
                        ],
                      ),
                      if (_beatSync) ...[
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
