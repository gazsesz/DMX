import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/live/live_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/l10n.dart';
import '../../models/layer.dart';
import '../../models/live_grid.dart';
import '../../state/artnet_providers.dart';
import '../../state/fixture_group_providers.dart';
import '../../state/layer_providers.dart';
import '../../state/live_providers.dart';
import '../../state/playback_providers.dart';
import 'live_clip_editor.dart';

/// Tablet layout from this width; below it the phone layout shows one lane
/// at a time.
const liveTabletBreakpoint = 840.0;

String liveQuantizeLabel(AppLocalizations l, LiveQuantize q) => switch (q) {
  LiveQuantize.now => l.liveQuantizeNow,
  LiveQuantize.beat => l.liveQuantizeBeat,
  LiveQuantize.bar => l.liveQuantizeBar,
};

String liveTargetLabel(AppLocalizations l, LiveTargetKind t) => switch (t) {
  LiveTargetKind.all => l.liveTargetAll,
  LiveTargetKind.heads => l.liveTargetHeads,
  LiveTargetKind.pars => l.liveTargetPars,
  LiveTargetKind.groups => l.liveTargetGroups,
};

String liveSpeedLabel(double speed) => switch (speed) {
  0.25 => '¼',
  0.5 => '½',
  _ => '×${speed.toStringAsFixed(0)}',
};

String liveLaneKindLabel(LiveLaneKind kind) => switch (kind) {
  LiveLaneKind.moves => 'Moves',
  LiveLaneKind.colors => 'Colors',
  LiveLaneKind.level => 'Level',
  LiveLaneKind.beam => 'Beam',
  LiveLaneKind.show => 'Show',
};

/// The second line under a lane's name: its fixtures, or for a Show lane
/// the layer its Banks / Scenes play on.
String liveLaneSubtitle(BuildContext context, WidgetRef ref, LiveLane lane) {
  if (lane.kind != LiveLaneKind.show) return liveTargetLabel(context.l10n, lane.target);
  final layers = ref.watch(layersProvider);
  for (final layer in layers) {
    if (layer.id == (lane.layerId ?? layer1Id)) return layer.name;
  }
  return layers.isEmpty ? '' : layers.first.name;
}

/// The BPM and where in the bar the clock is. A tap makes this beat the
/// first of the bar.
class LiveClockChip extends ConsumerWidget {
  const LiveClockChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(liveStatusProvider);
    return Tooltip(
      message: context.l10n.liveDownbeatHint,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => ref.read(liveEngineProvider).markDownbeat(),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: AppColors.panel2, borderRadius: BorderRadius.circular(10)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                status.bpm.toStringAsFixed(1),
                style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 18),
              ),
              const SizedBox(width: 6),
              const Text('BPM', style: TextStyle(color: AppColors.textDim, fontSize: 11)),
              const SizedBox(width: 10),
              for (var i = 1; i <= 4; i++)
                Container(
                  key: ValueKey('beat-$i'),
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    color: status.anyRunning && status.beatInBar == i ? AppColors.accent : AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class LiveGridView extends ConsumerWidget {
  const LiveGridView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Make sure the engine exists (and hears beats) while the screen is up.
    ref.watch(liveEngineProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= liveTabletBreakpoint) {
          return const Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _GridTable()),
              SizedBox(width: 240, child: _SidePanel()),
            ],
          );
        }
        return const _PhoneGrid();
      },
    );
  }
}

// --- Actions shared by both layouts -----------------------------------------

void _tapClip(BuildContext context, WidgetRef ref, LiveLane lane, int row) {
  final grid = ref.read(liveGridProvider);
  if (grid.clipAt(lane.id, row) == null) {
    _editClip(context, ref, lane, row);
    return;
  }
  final prefs = ref.read(livePrefsProvider);
  ref.read(liveEngineProvider).select(lane.id, row, mode: prefs.padMode, quantize: prefs.quantize);
}

void _tapRow(WidgetRef ref, int row) {
  final prefs = ref.read(livePrefsProvider);
  ref.read(liveEngineProvider).selectRow(row, mode: prefs.padMode, quantize: prefs.quantize);
}

Future<void> _editClip(BuildContext context, WidgetRef ref, LiveLane lane, int row) async {
  final grid = ref.read(liveGridProvider);
  final result = await showLiveClipEditor(context, lane: lane, clip: grid.clipAt(lane.id, row));
  if (result == null) return;
  ref.read(liveGridProvider.notifier).setClip(lane.id, row, result.delete ? null : result.clip);
  if (result.delete && ref.read(liveStatusProvider).running[lane.id] == row) {
    ref.read(liveEngineProvider).stopLane(lane.id);
  }
}

Future<void> _renameRow(BuildContext context, WidgetRef ref, int row) async {
  final rows = ref.read(liveGridProvider).rows;
  final name = await _askName(context, context.l10n.liveRenameRow, row < rows.length ? rows[row] : '');
  if (name != null && name.trim().isNotEmpty) ref.read(liveGridProvider.notifier).renameRow(row, name.trim());
}

Future<void> _addRow(BuildContext context, WidgetRef ref) async {
  final name = await _askName(context, context.l10n.liveAddRow, '');
  if (name != null && name.trim().isNotEmpty) ref.read(liveGridProvider.notifier).addRow(name.trim());
}

Future<String?> _askName(BuildContext context, String title, String initial) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: context.l10n.commonName),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.commonCancel)),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(context.l10n.commonSave)),
      ],
    ),
  );
}

Future<void> _addLane(BuildContext context, WidgetRef ref) async {
  final kind = await showDialog<LiveLaneKind>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(context.l10n.liveAddLane),
      children: [
        for (final k in LiveLaneKind.values)
          SimpleDialogOption(
            key: ValueKey('live-add-lane-${k.name}'),
            onPressed: () => Navigator.pop(context, k),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(liveLaneKindLabel(k))),
          ),
      ],
    ),
  );
  if (kind == null) return;
  final grid = ref.read(liveGridProvider);
  ref
      .read(liveGridProvider.notifier)
      .addLane(
        LiveLane(
          id: grid.freeLaneId(kind.name),
          name: liveLaneKindLabel(kind),
          kind: kind,
          target: kind == LiveLaneKind.moves || kind == LiveLaneKind.beam ? LiveTargetKind.heads : LiveTargetKind.all,
        ),
      );
}

Future<void> _laneSettings(BuildContext context, WidgetRef ref, LiveLane lane) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => _LaneSettingsSheet(laneId: lane.id),
  );
}

// --- Tablet ------------------------------------------------------------------

class _GridTable extends ConsumerWidget {
  const _GridTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grid = ref.watch(liveGridProvider);
    final l = context.l10n;
    const sceneWidth = 112.0;
    const gap = 8.0;
    const addWidth = 44.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: sceneWidth,
                child: Text(
                  l.liveScenes,
                  style: const TextStyle(color: AppColors.textDim, fontSize: 11, letterSpacing: 0.8),
                ),
              ),
              for (final lane in grid.lanes) ...[const SizedBox(width: gap), Expanded(child: _LaneHeader(lane: lane))],
              const SizedBox(width: gap),
              SizedBox(
                width: addWidth,
                child: IconButton.outlined(
                  key: const ValueKey('live-add-lane'),
                  tooltip: l.liveAddLane,
                  onPressed: () => _addLane(context, ref),
                  icon: const Icon(Icons.add),
                ),
              ),
            ],
          ),
          const SizedBox(height: gap),
          Expanded(
            child: ListView(
              children: [
                for (var row = 0; row < grid.rows.length; row++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: gap),
                    child: SizedBox(
                      height: 84,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: sceneWidth,
                            child: _SceneButton(row: row),
                          ),
                          for (final lane in grid.lanes) ...[
                            const SizedBox(width: gap),
                            Expanded(
                              child: _ClipCell(lane: lane, row: row),
                            ),
                          ],
                          const SizedBox(width: gap + addWidth),
                        ],
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _addRow(context, ref),
                    icon: const Icon(Icons.add),
                    label: Text(l.liveAddRow),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: gap),
          Row(
            children: [
              const SizedBox(width: sceneWidth),
              for (final lane in grid.lanes) ...[const SizedBox(width: gap), Expanded(child: _LaneFooter(lane: lane))],
              const SizedBox(width: gap + addWidth),
            ],
          ),
        ],
      ),
    );
  }
}

class _LaneHeader extends ConsumerWidget {
  final LiveLane lane;
  const _LaneHeader({required this.lane});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(liveStatusProvider.select((s) => s.running.containsKey(lane.id)));
    return Material(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _laneSettings(context, ref, lane),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lane.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    Text(
                      liveLaneSubtitle(context, ref, lane),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textDim, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (running) const Icon(Icons.graphic_eq, size: 16, color: AppColors.accent2),
            ],
          ),
        ),
      ),
    );
  }
}

class _LaneFooter extends ConsumerWidget {
  final LiveLane lane;
  const _LaneFooter({required this.lane});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Row(
      children: [
        if (lane.kind == LiveLaneKind.show)
          const Spacer()
        else
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), padding: EdgeInsets.zero),
              onPressed: () {
                final i = liveLaneSpeeds.indexOf(lane.speed);
                final next = liveLaneSpeeds[(i + 1) % liveLaneSpeeds.length];
                ref.read(liveGridProvider.notifier).updateLane(lane.copyWith(speed: next));
              },
              child: Text('${l.liveLaneSpeed} ${liveSpeedLabel(lane.speed)}', style: const TextStyle(fontSize: 12)),
            ),
          ),
        const SizedBox(width: 6),
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton.outlined(
            tooltip: l.liveLaneStop,
            onPressed: () => ref.read(liveEngineProvider).stopLane(lane.id),
            icon: const Icon(Icons.stop, size: 18),
          ),
        ),
      ],
    );
  }
}

class _SceneButton extends ConsumerWidget {
  final int row;
  const _SceneButton({required this.row});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(liveGridProvider.select((g) => g.rows));
    final status = ref.watch(liveStatusProvider);
    final live = status.running.values.contains(row);
    return Material(
      color: live ? AppColors.border : AppColors.panel2,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _tapRow(ref, row),
        onLongPress: () => _renameRow(context, ref, row),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  row < rows.length ? rows[row] : '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              const Icon(Icons.play_arrow_rounded, size: 18, color: AppColors.textDim),
            ],
          ),
        ),
      ),
    );
  }
}

/// One cell: empty, ready, NEXT (amber), armed (amber, counting down) or
/// running (cyan).
class _ClipCell extends ConsumerWidget {
  final LiveLane lane;
  final int row;
  const _ClipCell({required this.lane, required this.row});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clip = ref.watch(liveGridProvider.select((g) => g.clipAt(lane.id, row)));
    final status = ref.watch(liveStatusProvider);
    return LiveClipTile(
      clip: clip,
      running: status.running[lane.id] == row,
      next: status.queued[lane.id] == row,
      armedIn: status.queued[lane.id] == row && status.armedAt[lane.id] != null
          ? (status.armedAt[lane.id]! - status.beat).ceil().clamp(0, 99)
          : null,
      onTap: () => _tapClip(context, ref, lane, row),
      onLongPress: () => _editClip(context, ref, lane, row),
    );
  }
}

class LiveClipTile extends StatelessWidget {
  final LiveClip? clip;
  final bool running;
  final bool next;
  final int? armedIn;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const LiveClipTile({
    super.key,
    required this.clip,
    required this.running,
    required this.next,
    required this.armedIn,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = clip;
    final Color bg;
    final Border border;
    if (c == null) {
      bg = AppColors.background;
      border = Border.all(color: AppColors.border);
    } else if (next) {
      bg = const Color(0xFF2A2010);
      border = Border.all(color: AppColors.accent, width: 2);
    } else if (running) {
      bg = const Color(0xFF0F3138);
      border = Border.all(color: AppColors.accent2);
    } else {
      bg = AppColors.panel2;
      border = Border.all(color: AppColors.border);
    }
    return Semantics(
      button: true,
      label: c?.name ?? l.liveNewClip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Ink(
            decoration: BoxDecoration(color: bg, border: border, borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: c == null
                  ? const Center(child: Icon(Icons.add, size: 18, color: AppColors.textFaint))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        Text(
                          clipSummary(c),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textDim, fontSize: 11),
                        ),
                        const Spacer(),
                        if (next)
                          Text(
                            armedIn == null ? 'NEXT' : 'NEXT · ${l.liveArmedIn(armedIn!)}',
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          )
                        else if (running)
                          Text(
                            l.liveRunning,
                            style: const TextStyle(color: AppColors.accent2, fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

String _beats(double b) => b == b.roundToDouble() ? b.toStringAsFixed(0) : b.toString();

/// One line under a clip's name: what it does and how fast.
String clipSummary(LiveClip clip) {
  if (clip.show != null) {
    return switch (clip.show!.kind) {
      LiveShowKind.bank => 'Bank',
      LiveShowKind.chase => 'Chase',
      LiveShowKind.scene => 'Scene',
    };
  }
  if (clip.moves != null) {
    final m = clip.moves!;
    final timing = m.beatLocked ? '${_beats(m.beats)} beats' : '${m.periodSec.toStringAsFixed(0)} s';
    return '${m.shape.name} · $timing';
  }
  if (clip.colors != null) {
    final c = clip.colors!;
    return c.pattern == LiveColorPattern.solid ? 'solid' : '${c.pattern.name} · ${_beats(c.beats)} beats';
  }
  if (clip.level != null) {
    final v = clip.level!;
    final range = '${(v.low * 100).round()}–${(v.high * 100).round()}%';
    return v.pattern == LiveLevelPattern.solid ? '${(v.high * 100).round()}%' : '${v.pattern.name} · $range';
  }
  if (clip.beam != null) {
    final b = clip.beam!;
    final parts = [
      if (b.strobe != null) b.strobe! <= 0 ? 'open' : 'strobe ${(b.strobe! * 100).round()}%',
      if (b.gobo != null) 'gobo ${b.gobo}',
      if (b.zoom != null) 'zoom ${(b.zoom! * 100).round()}%',
      if (b.prism != null) b.prism! <= 0 ? 'prism out' : 'prism',
      if (b.prismRotation != null) 'prism rot ${(b.prismRotation! * 100).round()}%',
    ];
    return parts.isEmpty ? '—' : parts.join(' · ');
  }
  return '';
}

class _SidePanel extends ConsumerWidget {
  const _SidePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final prefs = ref.watch(livePrefsProvider);
    final status = ref.watch(liveStatusProvider);
    final grid = ref.watch(liveGridProvider);
    final engine = ref.read(liveEngineProvider);
    final master = ref.watch(grandMasterProvider);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.liveLaunch, style: const TextStyle(color: AppColors.textDim, fontSize: 11, letterSpacing: 0.8)),
            const SizedBox(height: 6),
            const _QuantizeSelector(),
            const SizedBox(height: 12),
            _NextSummary(status: status, grid: grid),
            const SizedBox(height: 12),
            SizedBox(
              height: 84,
              child: FilledButton(
                key: const ValueKey('live-go'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.accentOn,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: status.queued.isEmpty ? null : () => engine.go(quantize: prefs.quantize),
                child: Text(l.liveGo, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Text(l.liveMain, style: const TextStyle(color: AppColors.textDim, fontSize: 11)),
                        Expanded(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: Slider(
                              value: master,
                              onChanged: (v) => ref.read(grandMasterProvider.notifier).set(v),
                            ),
                          ),
                        ),
                        Text('${(master * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 104,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _PanelButton(
                            label: l.liveFreeze,
                            active: status.frozen,
                            onPressed: () => engine.setFrozen(!status.frozen),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: _PanelButton(label: l.liveStopAll, onPressed: engine.stopAll),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: _PanelButton(
                            label: l.commonBlackout,
                            danger: true,
                            onPressed: () {
                              engine.stopAll();
                              blackoutEverything(ref.read);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l.livePadsHint(prefs.padMode == LivePadMode.selectThenGo ? l.livePadsSelectGo : l.livePadsDirect),
              style: const TextStyle(color: AppColors.textDim, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuantizeSelector extends ConsumerWidget {
  const _QuantizeSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quantize = ref.watch(livePrefsProvider.select((p) => p.quantize));
    return SegmentedButton<LiveQuantize>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        for (final q in LiveQuantize.values) ButtonSegment(value: q, label: Text(liveQuantizeLabel(context.l10n, q))),
      ],
      selected: {quantize},
      onSelectionChanged: (s) => ref.read(livePrefsProvider.notifier).setQuantize(s.first),
    );
  }
}

class _NextSummary extends StatelessWidget {
  final LiveStatus status;
  final LiveGrid grid;
  const _NextSummary({required this.status, required this.grid});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (status.queued.isEmpty) {
      return Text(l.liveNextNone, style: const TextStyle(color: AppColors.textDim, fontSize: 12));
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2010),
        border: Border.all(color: AppColors.accent),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in status.queued.entries)
            Text(
              '${grid.lane(e.key)?.name ?? e.key} → ${grid.clipAt(e.key, e.value)?.name ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool active;
  final bool danger;
  const _PanelButton({required this.label, required this.onPressed, this.active = false, this.danger = false});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.zero,
        backgroundColor: active ? AppColors.accent2 : (danger ? const Color(0xFF2A1416) : AppColors.panel2),
        foregroundColor: active ? AppColors.accent2On : (danger ? const Color(0xFFFFB4B4) : AppColors.text),
        side: BorderSide(color: danger ? const Color(0xFF5A2A2A) : AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onPressed,
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}

// --- Phone -------------------------------------------------------------------

class _PhoneGrid extends ConsumerStatefulWidget {
  const _PhoneGrid();

  @override
  ConsumerState<_PhoneGrid> createState() => _PhoneGridState();
}

class _PhoneGridState extends ConsumerState<_PhoneGrid> {
  String? _laneId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final grid = ref.watch(liveGridProvider);
    final status = ref.watch(liveStatusProvider);
    final prefs = ref.watch(livePrefsProvider);
    final engine = ref.read(liveEngineProvider);
    if (grid.lanes.isEmpty) return const SizedBox.shrink();
    final lane = grid.lane(_laneId ?? '') ?? grid.lanes.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final ln in grid.lanes)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text('${ln.name} · ${liveLaneSubtitle(context, ref, ln)}'),
                    avatar: status.running.containsKey(ln.id) ? const Icon(Icons.graphic_eq, size: 16) : null,
                    selected: ln.id == lane.id,
                    onSelected: (_) => setState(() => _laneId = ln.id),
                  ),
                ),
              ActionChip(
                key: const ValueKey('live-add-lane'),
                avatar: const Icon(Icons.add, size: 16),
                label: Text(l.liveAddLane),
                onPressed: () => _addLane(context, ref),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: grid.rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, row) => SizedBox(
              height: 64,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 88, child: _SceneButton(row: row)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ClipCell(lane: lane, row: row),
                  ),
                ],
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          decoration: const BoxDecoration(
            color: AppColors.panel,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: _QuantizeSelector()),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: l.liveLaneSettings,
                    onPressed: () => _laneSettings(context, ref, lane),
                    icon: const Icon(Icons.tune),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.accentOn,
                        ),
                        onPressed: status.queued.isEmpty ? null : () => engine.go(quantize: prefs.quantize),
                        child: Text(l.liveGo, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 56,
                    child: OutlinedButton(
                      onPressed: () => engine.setFrozen(!status.frozen),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: status.frozen ? AppColors.accent2 : null,
                        foregroundColor: status.frozen ? AppColors.accent2On : null,
                      ),
                      child: Text(l.liveFreeze),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 56,
                    child: OutlinedButton(onPressed: engine.stopAll, child: Text(l.commonStop)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- Lane settings -------------------------------------------------------------

class _LaneSettingsSheet extends ConsumerWidget {
  final String laneId;
  const _LaneSettingsSheet({required this.laneId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final lane = ref.watch(liveGridProvider.select((g) => g.lane(laneId)));
    final groups = ref.watch(fixtureGroupsProvider);
    final layers = ref.watch(layersProvider);
    if (lane == null) return const SizedBox.shrink();
    void update(LiveLane next) => ref.read(liveGridProvider.notifier).updateLane(next);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${lane.name} · ${liveLaneKindLabel(lane.kind)}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            if (lane.kind == LiveLaneKind.show) ...[
              Text(l.liveLaneLayer, style: const TextStyle(color: AppColors.textDim)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final layer in layers)
                    ChoiceChip(
                      label: Text(layer.name),
                      selected: (lane.layerId ?? layer1Id) == layer.id,
                      onSelected: (_) => update(lane.copyWith(layerId: layer.id)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(l.liveLaneLayerHint, style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
            ] else ...[
              Text(l.liveLaneTarget, style: const TextStyle(color: AppColors.textDim)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final t in LiveTargetKind.values)
                    if (t != LiveTargetKind.groups || groups.isNotEmpty)
                      ChoiceChip(
                        label: Text(liveTargetLabel(l, t)),
                        selected: lane.target == t,
                        onSelected: (_) => update(lane.copyWith(target: t)),
                      ),
                ],
              ),
              if (lane.target == LiveTargetKind.groups) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final g in groups)
                      FilterChip(
                        label: Text(g.name),
                        selected: lane.groupIds.contains(g.id),
                        onSelected: (on) => update(
                          lane.copyWith(
                            groupIds: on
                                ? [...lane.groupIds, g.id]
                                : [
                                    for (final id in lane.groupIds)
                                      if (id != g.id) id,
                                  ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Text(l.liveLaneSpeed, style: const TextStyle(color: AppColors.textDim)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final s in liveLaneSpeeds)
                    ChoiceChip(
                      label: Text(liveSpeedLabel(s)),
                      selected: lane.speed == s,
                      onSelected: (_) => update(lane.copyWith(speed: s)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    ref.read(liveEngineProvider).stopLane(lane.id);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.stop),
                  label: Text(l.liveLaneStop),
                ),
                TextButton.icon(
                  key: const ValueKey('live-delete-lane'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: () {
                    ref.read(liveEngineProvider).stopLane(lane.id);
                    ref.read(liveGridProvider.notifier).removeLane(lane.id);
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l.liveDeleteLane),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
