import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/positions/aim.dart';
import '../../../core/positions/group_positions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/channel_slider.dart';
import '../../../core/widgets/pan_tilt_pad.dart';
import '../../../models/channel_capability.dart';
import '../../../models/group_position.dart';
import '../../../models/pan_tilt.dart';
import '../../../models/patched_fixture.dart';
import '../../../models/position_preset.dart';
import '../../fixtures/fixture_mounting_sheet.dart';
import '../../../models/stage_plan.dart';
import '../../../state/fixture_providers.dart';
import '../../../state/stage_providers.dart';
import 'stage_aim_view.dart';
import '../../../l10n/l10n.dart';

/// The Scene editor's Position tab for one group of movers: an XY pad (or
/// the stage-aim view), saved positions, the fan, and pan/tilt speed.
///
/// It owns nothing but view state (coarse/fine). Every change goes back to
/// the editor through the callbacks, which keeps the editor's group values
/// the single source the scene is saved from.
class PositionPanel extends ConsumerStatefulWidget {
  /// The group's heads that have pan and/or tilt.
  final List<PatchedFixture> fixtures;
  final PanTilt base;
  final GroupPosition position;
  final Map<String, ResolvedPosition> resolved;

  /// The pan/tilt speed channel's value and ranges, or null when no head in
  /// the group has one.
  final int? speed;
  final List<ChannelCapability> speedCapabilities;

  /// The pad's shared handle was dragged: the editor moves every head set on
  /// its own along by the same amount.
  final ValueChanged<PanTilt> onBaseDragged;

  /// Replace the shared position and the group settings outright.
  final void Function(PanTilt base, GroupPosition position) onReplace;
  final ValueChanged<int> onSpeedChanged;

  /// A head's rigging or calibration changed — the editor puts the heads
  /// back on their targets so it can be watched on the rig as it is dialled.
  final VoidCallback? onRiggingChanged;

  const PositionPanel({
    super.key,
    required this.fixtures,
    required this.base,
    required this.position,
    required this.resolved,
    required this.onBaseDragged,
    required this.onReplace,
    required this.onSpeedChanged,
    this.onRiggingChanged,
    this.speed,
    this.speedCapabilities = const [],
  });

  @override
  ConsumerState<PositionPanel> createState() => _PositionPanelState();
}

class _PositionPanelState extends ConsumerState<PositionPanel> {
  bool _fine = false;
  /// The pad's grid snap, kept with the group in the scene so it reopens
  /// the same way.
  PadSnap get _snap => PadSnap.values.firstWhere((s) => s.cell == widget.position.snapCell, orElse: () => PadSnap.off);

  void _setSnap(PadSnap snap) => widget.onReplace(widget.base, widget.position.copyWith(snapCell: snap.cell));

  int get _panRange => widget.fixtures.isEmpty ? 540 : widget.fixtures.first.profile.panRangeDeg;
  int get _tiltRange => widget.fixtures.isEmpty ? 270 : widget.fixtures.first.profile.tiltRangeDeg;

  List<PadMarker> get _markers => [
    for (final fixture in widget.fixtures)
      if (widget.resolved[fixture.id] case final r?) PadMarker(r.position, fixture.label),
  ];

  // ---- mode switching -----------------------------------------------------

  void _setMode(PositionMode mode) {
    if (mode == widget.position.mode) return;
    final stage = ref.read(stagePlanProvider);
    if (mode == PositionMode.stage) {
      widget.onReplace(widget.base, enterStageMode(widget.position, widget.resolved, widget.fixtures, stage));
    } else {
      final ordered = spreadOrder(widget.fixtures);
      final first = ordered.isEmpty ? null : widget.resolved[ordered.first.id]?.position;
      widget.onReplace(first ?? widget.base, enterPadMode(widget.position, widget.resolved));
    }
  }

  // ---- presets ------------------------------------------------------------

  void _applyPreset(PositionPreset preset) {
    final ids = widget.fixtures.map((f) => f.id).toSet();
    final matching = {
      for (final e in preset.perFixture.entries)
        if (ids.contains(e.key)) e.key: e.value,
    };
    if (matching.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.scHasNoPositionSaved(preset.name))),
      );
      return;
    }
    final first = spreadOrder(widget.fixtures).map((f) => matching[f.id]).whereType<PanTilt>().first;
    widget.onReplace(
      first,
      widget.position.copyWith(mode: PositionMode.pad, manual: {...widget.position.manual, ...matching}),
    );
  }

  Map<String, PanTilt> get _currentPositions => {
    for (final e in widget.resolved.entries) e.key: e.value.position,
  };

  Future<void> _saveAsPreset() async {
    final name = await _askName(context, title: context.l10n.scSavePosition, initial: '');
    if (name == null || !mounted) return;
    ref.read(positionPresetsProvider.notifier).create(name: name, perFixture: _currentPositions);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.filesSaved(name))));
  }

  Future<void> _presetMenu(PositionPreset preset) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.panel,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.save_alt, color: AppColors.accent),
              title: Text(context.l10n.scUpdateWithThesePositions(preset.name)),
              subtitle: Text(context.l10n.scOnlyTheseFixturesChange),
              onTap: () => Navigator.pop(context, 'update'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(context.l10n.scRename),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.danger),
              title: Text(context.l10n.scDelete, style: TextStyle(color: AppColors.danger)),
              subtitle: Text(context.l10n.scScenesThatUsedIt),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    final notifier = ref.read(positionPresetsProvider.notifier);
    switch (action) {
      case 'update':
        notifier.merge(preset.id, _currentPositions);
      case 'rename':
        final name = await _askName(context, title: context.l10n.scRenamePosition, initial: preset.name);
        if (name != null) notifier.rename(preset.id, name);
      case 'delete':
        notifier.remove(preset.id);
    }
  }

  // ---- per fixture ----------------------------------------------------------

  Future<void> _perFixture() async {
    var position = widget.position.mode == PositionMode.stage
        ? enterPadMode(widget.position, widget.resolved)
        : widget.position;
    var base = widget.base;
    final positions = _currentPositions;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.panel,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          void setFixture(String id, PanTilt value) {
            positions[id] = value;
            position = position.copyWith(manual: {...position.manual, id: value});
            setSheetState(() {});
            widget.onReplace(base, position);
          }

          void reset(String id) {
            position = position.copyWith(manual: {...position.manual}..remove(id));
            setSheetState(() {});
            widget.onReplace(base, position);
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                children: [
                  Text(
                    context.l10n.scPerFixture,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
                  ),
                  Text(
                    context.l10n.scAHeadSetHere,
                    style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
                  ),
                  const SizedBox(height: 8),
                  for (final fixture in spreadOrder(widget.fixtures)) ...[
                    _perFixtureRow(
                      fixture,
                      positions[fixture.id] ?? base,
                      ownSpot: position.manual.containsKey(fixture.id),
                      onChanged: (value) => setFixture(fixture.id, value),
                      onReset: () => reset(fixture.id),
                    ),
                    const Divider(height: 18),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _perFixtureRow(
    PatchedFixture fixture,
    PanTilt value, {
    required bool ownSpot,
    required ValueChanged<PanTilt> onChanged,
    required VoidCallback onReset,
  }) {
    final panRange = fixture.profile.panRangeDeg;
    final tiltRange = fixture.profile.tiltRangeDeg;
    Widget axis(String label, int raw, int range, ValueChanged<int> set) {
      return Row(
        children: [
          SizedBox(width: 34, child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textDim))),
          Expanded(
            child: Slider(
              value: raw.toDouble(),
              max: PanTilt.max.toDouble(),
              onChanged: (v) => set(v.round()),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              '${(raw / PanTilt.max * range).toStringAsFixed(1)}°',
              textAlign: TextAlign.right,
              style: appMonoStyle(fontSize: 11),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(fixture.label, style: const TextStyle(fontWeight: FontWeight.w700))),
            if (ownSpot)
              TextButton(onPressed: onReset, child: Text(context.l10n.scBackToGroup)),
          ],
        ),
        axis('Pan', value.pan, panRange, (v) => onChanged(PanTilt(v, value.tilt))),
        axis('Tilt', value.tilt, tiltRange, (v) => onChanged(PanTilt(value.pan, v))),
      ],
    );
  }

  // ---- full-screen pad ------------------------------------------------------

  Future<void> _fullscreenPad() async {
    var current = widget.base;
    var fine = _fine;
    var snap = _snap;
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: AppColors.background,
        child: StatefulBuilder(
          builder: (context, setDialogState) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(context.l10n.scPosition, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      ),
                      _CoarseFineToggle(fine: fine, onChanged: (v) => setDialogState(() => fine = v)),
                      if (!fine) ...[
                        const SizedBox(width: 8),
                        _SnapToggle(
                          snap: snap,
                          onChanged: (v) => setDialogState(() {
                            snap = v;
                            _setSnap(v);
                          }),
                        ),
                      ],
                      IconButton(
                        tooltip: context.l10n.commonDone,
                        icon: const Icon(Icons.close_fullscreen),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Expanded(
                    child: Center(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // The pad is 0.72 as tall as it is wide; fit it
                          // to whichever side runs out first.
                          final width = constraints.maxWidth.clamp(0.0, constraints.maxHeight / 0.72);
                          return SizedBox(
                            width: width,
                            child: PanTiltPad(
                              value: current,
                              fine: fine,
                              snap: snap,
                              panRangeDeg: _panRange,
                              tiltRangeDeg: _tiltRange,
                              onChanged: (value) {
                                setDialogState(() => current = value);
                                widget.onBaseDragged(value);
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final stage = ref.watch(stagePlanProvider);
    final isStage = widget.position.mode == PositionMode.stage;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640;
        final main = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<PositionMode>(
                  showSelectedIcon: false,
                  style: _segmentStyle,
                  segments: [
                    ButtonSegment(value: PositionMode.pad, label: Text(context.l10n.scXyPad)),
                    ButtonSegment(value: PositionMode.stage, label: Text(context.l10n.scStage)),
                  ],
                  selected: {widget.position.mode},
                  onSelectionChanged: (s) => _setMode(s.first),
                ),
                if (!isStage) ...[
                  _CoarseFineToggle(fine: _fine, onChanged: (v) => setState(() => _fine = v)),
                  if (!_fine) _SnapToggle(snap: _snap, onChanged: _setSnap),
                  IconButton(
                    tooltip: context.l10n.scFullScreen,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.open_in_full, size: 18),
                    onPressed: _fullscreenPad,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: isStage
                  ? StageAimView(
                      fixtures: widget.fixtures,
                      otherFixtures: ref
                          .watch(patchedFixturesProvider)
                          .where((f) => !widget.fixtures.any((g) => g.id == f.id))
                          .toList(),
                      stage: stage,
                      position: widget.position,
                      resolved: widget.resolved,
                      onChanged: (position) => widget.onReplace(widget.base, position),
                    )
                  : PanTiltPad(
                      value: widget.base,
                      markers: _markers,
                      fine: _fine,
                      snap: _snap,
                      panRangeDeg: _panRange,
                      tiltRangeDeg: _tiltRange,
                      onChanged: widget.onBaseDragged,
                    ),
            ),
            if (isStage && _layoutLooksUnset) ...[
              const SizedBox(height: 6),
              Text(
                context.l10n.scTipPlaceTheseHeads,
                style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
              ),
            ],
          ],
        );
        final side = isStage ? _stageControls(stage) : _padControls();
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(flex: 6, child: main),
              const SizedBox(width: 20),
              Flexible(flex: 5, child: side),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [main, const SizedBox(height: 14), side],
        );
      },
    );
  }

  bool get _layoutLooksUnset => widget.fixtures.every((f) => f.layoutX == 0.5 && f.layoutY == 0.5);

  Widget _presetChips() {
    final presets = ref.watch(positionPresetsProvider);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final preset in presets)
          GestureDetector(
            onLongPress: () => _presetMenu(preset),
            child: ActionChip(
              label: Text(preset.name, style: const TextStyle(fontSize: 11.5)),
              onPressed: () => _applyPreset(preset),
              tooltip: context.l10n.scTapToRecallLong,
            ),
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 16, color: AppColors.accent),
          label: Text(context.l10n.scSaveCurrent, style: TextStyle(fontSize: 11.5, color: AppColors.accent)),
          onPressed: _saveAsPreset,
        ),
      ],
    );
  }

  Widget _padControls() {
    final position = widget.position;
    final multiple = widget.fixtures.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _label(context.l10n.scPositionPresets),
        _presetChips(),
        if (multiple) ...[
          const SizedBox(height: 14),
          _label(context.l10n.scGroupSpread),
          _degreeSlider(
            context.l10n.scFanPan,
            position.fanPanDeg,
            -60,
            60,
            (v) => widget.onReplace(widget.base, position.copyWith(fanPanDeg: v)),
          ),
          _degreeSlider(
            context.l10n.scFanTilt,
            position.fanTiltDeg,
            -30,
            30,
            (v) => widget.onReplace(widget.base, position.copyWith(fanTiltDeg: v)),
          ),
          Wrap(
            spacing: 6,
            children: [
              FilterChip(
                label: Text(context.l10n.scMirrorLeftRight, style: TextStyle(fontSize: 11.5)),
                selected: position.mirror,
                tooltip: context.l10n.scHeadsOnTheRight,
                onSelected: (v) => widget.onReplace(widget.base, position.copyWith(mirror: v)),
              ),
            ],
          ),
          if (position.manual.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                context.l10n.scOfHeadsHaveTheir(position.manual.length, widget.fixtures.length),
                style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint),
              ),
            ),
        ],
        if (widget.speed != null) ...[
          const SizedBox(height: 10),
          _label(context.l10n.scMovement),
          LabeledChannelSlider(
            label: context.l10n.scPanTiltSpeed,
            value: widget.speed!,
            color: AppColors.accent2,
            capabilities: widget.speedCapabilities,
            onChanged: widget.onSpeedChanged,
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            if (multiple)
              Expanded(
                child: OutlinedButton(onPressed: _perFixture, child: Text(context.l10n.scPerFixture2)),
              ),
            if (multiple) const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => widget.onReplace(PanTilt.center, const GroupPosition()),
                child: Text(context.l10n.scCenterAll),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stageControls(StagePlan stage) {
    final position = widget.position;
    final unreachable = widget.resolved.values.where((r) => !r.reachable).length;
    void replace(GroupPosition p) => widget.onReplace(widget.base, p);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.fixtures.any((f) => f.mounting.isDefault))
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              border: Border.all(color: AppColors.accent),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              context.l10n.scDefaultRigging([for (final f in widget.fixtures) if (f.mounting.isDefault) f.label].join(', ')),
              style: const TextStyle(fontSize: 11, color: AppColors.textDim),
            ),
          ),
        _label(context.l10n.scRiggingCalibration),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final fixture in spreadOrder(widget.fixtures))
              ActionChip(
                avatar: Icon(
                  fixture.mounting.isDefault ? Icons.warning_amber_rounded : Icons.tune,
                  size: 16,
                  color: fixture.mounting.isDefault ? AppColors.accent : AppColors.textDim,
                ),
                label: Text(
                  '${fixture.label} · ${fixture.mounting.mount.label}${fixture.mounting.isCalibrated ? ' · cal' : ''}',
                  style: const TextStyle(fontSize: 11.5),
                ),
                tooltip: context.l10n.scRiggingThenCalibrateThis,
                onPressed: () => showFixtureMountingSheet(
                  context,
                  fixture.id,
                  mark: widget.resolved[fixture.id]?.target ?? position.handle,
                  markHeightM: position.aimHeightM,
                  onChanged: widget.onRiggingChanged,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _label(context.l10n.scAimAt),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ChoiceChip(
              label: Text(context.l10n.scFloor, style: TextStyle(fontSize: 11.5)),
              selected: position.aimHeightM == 0,
              onSelected: (_) => replace(position.copyWith(aimHeightM: 0)),
            ),
            ChoiceChip(
              label: Text(context.l10n.scHeads17M, style: TextStyle(fontSize: 11.5)),
              selected: position.aimHeightM == 1.7,
              tooltip: context.l10n.scTheAudienceSHead,
              onSelected: (_) => replace(position.copyWith(aimHeightM: 1.7)),
            ),
            for (final target in stage.targets)
              GestureDetector(
                onLongPress: () => _targetMenu(target),
                child: ChoiceChip(
                  label: Text(target.name, style: const TextStyle(fontSize: 11.5)),
                  selected: position.handle == StagePoint(target.x, target.y) && position.aimHeightM == target.heightM,
                  tooltip: context.l10n.scMHighLongPress(target.heightM.toStringAsFixed(1)),
                  onSelected: (_) => replace(
                    position.copyWith(
                      handle: StagePoint(target.x, target.y),
                      aimHeightM: target.heightM,
                      formation: StageFormation.point,
                      aimOverrides: const {},
                    ),
                  ),
                ),
              ),
            ActionChip(
              avatar: const Icon(Icons.add_location_alt_outlined, size: 16, color: AppColors.accent),
              label: Text(context.l10n.scSaveSpot, style: TextStyle(fontSize: 11.5, color: AppColors.accent)),
              tooltip: context.l10n.scNameTheSpotUnder,
              onPressed: () => _saveTarget(position),
            ),
          ],
        ),
        if (position.aimHeightM != 0 && position.aimHeightM != 1.7)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              context.l10n.scAimingMAboveThe(position.aimHeightM.toStringAsFixed(1)),
              style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint),
            ),
          ),
        if (widget.fixtures.length > 1) ...[
          const SizedBox(height: 14),
          _label(context.l10n.scFormation),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final formation in StageFormation.values)
                ChoiceChip(
                  label: Text(formation.label, style: const TextStyle(fontSize: 11.5)),
                  selected: position.formation == formation && position.aimOverrides.isEmpty,
                  onSelected: (_) => replace(position.copyWith(formation: formation, aimOverrides: const {})),
                ),
            ],
          ),
          if (position.formation != StageFormation.point)
            _meterSlider(
              context.l10n.scSpread,
              position.spreadM,
              (v) => replace(position.copyWith(spreadM: v)),
            ),
          if (position.aimOverrides.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => replace(position.copyWith(aimOverrides: const {})),
                child: Text(context.l10n.scBackToTheFormation(position.aimOverrides.length)),
              ),
            ),
        ],
        if (unreachable > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              context.l10n.scUnreachable(unreachable),
              style: const TextStyle(fontSize: 11, color: AppColors.danger),
            ),
          ),
        const SizedBox(height: 10),
        _aimReadout(),
        if (widget.speed != null) ...[
          const SizedBox(height: 10),
          _label(context.l10n.scMovement),
          LabeledChannelSlider(
            label: context.l10n.scPanTiltSpeed,
            value: widget.speed!,
            color: AppColors.accent2,
            capabilities: widget.speedCapabilities,
            onChanged: widget.onSpeedChanged,
          ),
        ],
        const SizedBox(height: 12),
        _presetChips(),
      ],
    );
  }

  Widget _aimReadout() {
    return Table(
      columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)},
      children: [
        TableRow(
          children: [
            const SizedBox.shrink(),
            Text('pan', style: appMonoStyle(fontSize: 10, color: AppColors.textFaint)),
            Text('tilt', style: appMonoStyle(fontSize: 10, color: AppColors.textFaint)),
          ],
        ),
        for (final fixture in spreadOrder(widget.fixtures))
          if (widget.resolved[fixture.id] case final r?)
            () {
              final (pan, tilt) = panTiltToDegrees(
                r.position,
                panRangeDeg: fixture.profile.panRangeDeg,
                tiltRangeDeg: fixture.profile.tiltRangeDeg,
              );
              final colour = r.reachable ? AppColors.textDim : AppColors.danger;
              return TableRow(
                children: [
                  Text(fixture.label, style: const TextStyle(fontSize: 11)),
                  Text('${(pan + fixture.profile.panRangeDeg / 2).toStringAsFixed(0)}°',
                      style: appMonoStyle(fontSize: 11, color: colour)),
                  Text('${(tilt + fixture.profile.tiltRangeDeg / 2).toStringAsFixed(0)}°',
                      style: appMonoStyle(fontSize: 11, color: colour)),
                ],
              );
            }(),
      ],
    );
  }

  Future<void> _saveTarget(GroupPosition position) async {
    final nameController = TextEditingController();
    final heightController = TextEditingController(text: position.aimHeightM.toStringAsFixed(1));
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text(context.l10n.scSaveSpot),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.scTheSpotUnderThe,
              style: TextStyle(fontSize: 11.5, color: AppColors.textFaint),
            ),
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(labelText: context.l10n.commonName, hintText: context.l10n.scMirrorBall),
            ),
            TextField(
              controller: heightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: context.l10n.scHeightAboveTheFloor, suffixText: 'm'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.l10n.commonSave)),
        ],
      ),
    );
    final name = nameController.text.trim();
    final height = double.tryParse(heightController.text.trim().replaceAll(',', '.')) ?? 0;
    if (saved != true || name.isEmpty || !mounted) return;
    ref.read(stagePlanProvider.notifier).addTarget(
      name: name,
      x: position.handle.x,
      y: position.handle.y,
      heightM: height,
    );
    widget.onReplace(widget.base, position.copyWith(aimHeightM: height.clamp(0.0, 50.0)));
  }

  Future<void> _targetMenu(AimTarget target) async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text(context.l10n.layersDeleteTitle(target.name)),
        content: Text(context.l10n.scScenesAlreadyAimedThere),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.scDelete),
          ),
        ],
      ),
    );
    if (delete == true) ref.read(stagePlanProvider.notifier).removeTarget(target.id);
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textFaint)),
  );

  Widget _degreeSlider(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 70, child: Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textDim))),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: (max - min).round(),
            onChanged: (v) => onChanged(v.roundToDouble()),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${value > 0 ? '+' : ''}${value.toStringAsFixed(0)}°',
            textAlign: TextAlign.right,
            style: appMonoStyle(fontSize: 11.5),
          ),
        ),
      ],
    );
  }

  Widget _meterSlider(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 70, child: Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textDim))),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, 8.0),
            max: 8,
            divisions: 32,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text('${value.toStringAsFixed(2)} m', textAlign: TextAlign.right, style: appMonoStyle(fontSize: 11)),
        ),
      ],
    );
  }
}

final _segmentStyle = SegmentedButton.styleFrom(
  visualDensity: VisualDensity.compact,
  textStyle: const TextStyle(fontFamily: appFontFamily, fontSize: 11.5, fontWeight: FontWeight.w700),
);

/// Where a coarse drag lands: anywhere, or on the pad's grid — whole 45° cells,
/// halves or quarters.
class _SnapToggle extends StatelessWidget {
  final PadSnap snap;
  final ValueChanged<PadSnap> onChanged;

  const _SnapToggle({required this.snap, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.l10n.scSnapToTheGrid,
      child: SegmentedButton<PadSnap>(
        showSelectedIcon: false,
        style: _segmentStyle,
        segments: [
          for (final s in PadSnap.values) ButtonSegment(value: s, label: Text(s == PadSnap.off ? context.l10n.scSnapOff : s.label)),
        ],
        selected: {snap},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class _CoarseFineToggle extends StatelessWidget {
  final bool fine;
  final ValueChanged<bool> onChanged;

  _CoarseFineToggle({required this.fine, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      style: _segmentStyle,
      segments: [
        ButtonSegment(value: false, label: Text(context.l10n.scCoarse)),
        ButtonSegment(value: true, label: Text(context.l10n.scFine)),
      ],
      selected: {fine},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

Future<String?> _askName(BuildContext context, {required String title, required String initial}) async {
  final controller = TextEditingController(text: initial);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: context.l10n.commonName, hintText: context.l10n.scAudience2),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.commonCancel)),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(context.l10n.commonSave)),
      ],
    ),
  );
  final trimmed = name?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
