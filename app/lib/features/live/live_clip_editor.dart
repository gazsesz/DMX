import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/live/live_engine.dart';
import '../../core/playback/color_override.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/l10n.dart';
import '../../models/channel_capability.dart';
import '../../models/channel_function.dart';
import '../../models/live_grid.dart';
import '../../models/movement_fx.dart';
import '../../state/artnet_providers.dart';
import '../../state/fixture_group_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/stage_providers.dart';

class LiveClipEditResult {
  final LiveClip? clip;
  final bool delete;
  const LiveClipEditResult.save(LiveClip this.clip) : delete = false;
  const LiveClipEditResult.delete() : clip = null, delete = true;
}

/// A fresh clip for [kind], before anyone edits it.
LiveClip defaultClipFor(LiveLaneKind kind) => switch (kind) {
  LiveLaneKind.moves => const LiveClip(
    name: 'Circle',
    moves: MovementFx(shape: MovementShape.circle, sizePanDeg: 30, sizeTiltDeg: 20, beatLocked: true, beats: 4),
  ),
  LiveLaneKind.colors => const LiveClip(name: 'White', colors: LiveColorFx()),
  LiveLaneKind.level => const LiveClip(name: 'Full', level: LiveLevelFx()),
  LiveLaneKind.beam => const LiveClip(name: 'Open', beam: LiveBeamFx(strobe: 0)),
};

Future<LiveClipEditResult?> showLiveClipEditor(BuildContext context, {required LiveLane lane, LiveClip? clip}) {
  return showModalBottomSheet<LiveClipEditResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _LiveClipEditor(lane: lane, initial: clip),
  );
}

const _beatChoices = <double>[0.5, 1, 2, 4, 8, 16];

String _title(String name) => name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);

class _LiveClipEditor extends ConsumerStatefulWidget {
  final LiveLane lane;
  final LiveClip? initial;
  const _LiveClipEditor({required this.lane, this.initial});

  @override
  ConsumerState<_LiveClipEditor> createState() => _LiveClipEditorState();
}

class _LiveClipEditorState extends ConsumerState<_LiveClipEditor> {
  late LiveClip _clip;
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    final base = defaultClipFor(widget.lane.kind);
    final initial = widget.initial;
    _clip = initial == null
        ? base
        : initial.copyWith(
            moves: initial.moves ?? base.moves,
            colors: initial.colors ?? base.colors,
            level: initial.level ?? base.level,
            beam: initial.beam ?? base.beam,
          );
    _name = TextEditingController(text: _clip.name);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _set(LiveClip next) => setState(() => _clip = next);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.initial == null ? l.liveNewClip : l.liveEditClip} · ${widget.lane.name}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(controller: _name, decoration: InputDecoration(labelText: l.commonName)),
            const SizedBox(height: 12),
            ...switch (widget.lane.kind) {
              LiveLaneKind.moves => _movesFields(),
              LiveLaneKind.colors => _colorFields(),
              LiveLaneKind.level => _levelFields(),
              LiveLaneKind.beam => _beamFields(),
            },
            const SizedBox(height: 16),
            Row(
              children: [
                if (widget.initial != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                    onPressed: () => Navigator.pop(context, const LiveClipEditResult.delete()),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(l.liveDeleteClip),
                  ),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(context), child: Text(l.commonCancel)),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final name = _name.text.trim().isEmpty ? _clip.name : _name.text.trim();
                    Navigator.pop(context, LiveClipEditResult.save(_onlyOwnKind(_clip.copyWith(name: name))));
                  },
                  child: Text(l.commonSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Keeps only the settings for this lane's kind, so the file stays small.
  LiveClip _onlyOwnKind(LiveClip c) => switch (widget.lane.kind) {
    LiveLaneKind.moves => LiveClip(name: c.name, moves: c.moves),
    LiveLaneKind.colors => LiveClip(name: c.name, colors: c.colors),
    LiveLaneKind.level => LiveClip(name: c.name, level: c.level),
    LiveLaneKind.beam => LiveClip(name: c.name, beam: c.beam),
  };

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 4),
    child: Text(text, style: const TextStyle(color: AppColors.textDim)),
  );

  Widget _beatsChips(double value, ValueChanged<double> onChanged) => Wrap(
    spacing: 6,
    children: [
      for (final b in _beatChoices)
        ChoiceChip(
          label: Text(b == 0.5 ? '½' : b.toStringAsFixed(0)),
          selected: value == b,
          onSelected: (_) => onChanged(b),
        ),
    ],
  );

  List<Widget> _movesFields() {
    final l = context.l10n;
    final m = _clip.moves!;
    void set(MovementFx fx) => _set(_clip.copyWith(moves: fx));
    final size = m.sizePanDeg.clamp(0.0, 90.0);
    return [
      _label(l.liveShape),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final shape in MovementShape.values)
            ChoiceChip(
              label: Text(_title(shape.name)),
              selected: m.shape == shape,
              onSelected: (_) {
                final preset = MovementFx.preset(shape);
                set(m.copyWith(shape: shape, sizePanDeg: preset.sizePanDeg, sizeTiltDeg: preset.sizeTiltDeg));
                if (_name.text.isEmpty || _name.text == _title(m.shape.name) || _name.text == _clip.name) {
                  _name.text = _title(shape.name);
                }
              },
            ),
        ],
      ),
      _label('${l.liveSize}: ${size.round()}°'),
      Slider(
        value: size,
        max: 90,
        onChanged: (v) {
          final ratio = m.sizePanDeg <= 0 ? 1.0 : m.sizeTiltDeg / m.sizePanDeg;
          set(m.copyWith(sizePanDeg: v, sizeTiltDeg: v * (m.sizePanDeg <= 0 ? 0.6 : ratio)));
        },
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l.liveBeatLocked),
        value: m.beatLocked,
        onChanged: (v) => set(m.copyWith(beatLocked: v)),
      ),
      if (m.beatLocked) ...[
        _label(l.liveBeats),
        _beatsChips(m.beats, (b) => set(m.copyWith(beats: b))),
      ] else ...[
        _label('${l.liveSecondsPerLap}: ${m.periodSec.toStringAsFixed(0)}'),
        Slider(value: m.periodSec.clamp(1.0, 30.0), min: 1, max: 30, divisions: 29, onChanged: (v) => set(m.copyWith(periodSec: v))),
      ],
      _label('${l.liveSpread}: ${(m.phaseSpread * 100).round()}%'),
      Slider(value: m.phaseSpread.clamp(0.0, 1.0), onChanged: (v) => set(m.copyWith(phaseSpread: v))),
    ];
  }

  List<Widget> _colorFields() {
    final l = context.l10n;
    final c = _clip.colors!;
    void set(LiveColorFx fx) => _set(_clip.copyWith(colors: fx));
    return [
      _label(l.livePattern),
      Wrap(
        spacing: 6,
        children: [
          for (final p in LiveColorPattern.values)
            ChoiceChip(label: Text(_title(p.name)), selected: c.pattern == p, onSelected: (_) => set(c.copyWith(pattern: p))),
        ],
      ),
      if (c.pattern != LiveColorPattern.rainbow) ...[
        _label(l.liveColors),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final color in liveColors)
              _ColorDot(
                color: color,
                index: c.colors.indexOf(_rgb(color)),
                onTap: () {
                  final rgb = _rgb(color);
                  final list = [...c.colors];
                  if (list.contains(rgb)) {
                    if (list.length > 1) list.remove(rgb);
                  } else {
                    list.add(rgb);
                  }
                  set(c.copyWith(colors: list));
                },
              ),
          ],
        ),
      ],
      if (c.pattern != LiveColorPattern.solid) ...[
        _label(l.liveBeats),
        _beatsChips(c.beats, (b) => set(c.copyWith(beats: b))),
        if (c.pattern == LiveColorPattern.step || c.pattern == LiveColorPattern.chase) ...[
          _label('${l.liveFade}: ${(c.fade * 100).round()}%'),
          Slider(value: c.fade.clamp(0.0, 1.0), onChanged: (v) => set(c.copyWith(fade: v))),
        ],
      ],
    ];
  }

  static int _rgb(LiveColor c) => (c.r << 16) | (c.g << 8) | c.b;

  List<Widget> _levelFields() {
    final l = context.l10n;
    final v = _clip.level!;
    void set(LiveLevelFx fx) => _set(_clip.copyWith(level: fx));
    return [
      _label(l.livePattern),
      Wrap(
        spacing: 6,
        children: [
          for (final p in LiveLevelPattern.values)
            ChoiceChip(label: Text(_title(p.name)), selected: v.pattern == p, onSelected: (_) => set(v.copyWith(pattern: p))),
        ],
      ),
      if (v.pattern == LiveLevelPattern.solid) ...[
        _label('${l.liveHigh}: ${(v.high * 100).round()}%'),
        Slider(value: v.high, onChanged: (x) => set(v.copyWith(high: x))),
      ] else ...[
        _label('${l.liveLow} ${(v.low * 100).round()}% – ${l.liveHigh} ${(v.high * 100).round()}%'),
        RangeSlider(
          values: RangeValues(v.low, v.high),
          onChanged: (r) => set(v.copyWith(low: r.start, high: r.end)),
        ),
        _label(l.liveBeats),
        _beatsChips(v.beats, (b) => set(v.copyWith(beats: b))),
        if (v.pattern != LiveLevelPattern.chase) ...[
          _label('${l.liveSpread}: ${(v.spread * 100).round()}%'),
          Slider(value: v.spread.clamp(0.0, 1.0), onChanged: (x) => set(v.copyWith(spread: x))),
        ],
      ],
    ];
  }

  List<Widget> _beamFields() {
    final l = context.l10n;
    final b = _clip.beam!;
    void set(LiveBeamFx fx) => _set(_clip.copyWith(beam: fx));
    final gobos = _goboSlots();
    final strobe = b.strobe ?? 0;
    return [
      _label('${l.liveStrobe}: ${strobe <= 0 ? l.liveStrobeOpen : '${(strobe * 100).round()}%'}'),
      Slider(value: strobe.clamp(0.0, 1.0), onChanged: (v) => set(b.copyWith(strobe: () => v))),
      _label(l.liveGobo),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          ChoiceChip(label: Text(l.liveLeaveAsIs), selected: b.gobo == null, onSelected: (_) => set(b.copyWith(gobo: () => null))),
          for (final cap in gobos)
            ChoiceChip(
              label: Text(cap.label),
              selected: b.gobo == cap.pickValue,
              onSelected: (_) => set(b.copyWith(gobo: () => cap.pickValue)),
            ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(l.liveZoom),
        value: b.zoom != null,
        onChanged: (on) => set(b.copyWith(zoom: () => on ? 0.5 : null)),
      ),
      if (b.zoom != null) Slider(value: b.zoom!.clamp(0.0, 1.0), onChanged: (v) => set(b.copyWith(zoom: () => v))),
    ];
  }

  /// Gobo slots of the first fixture this lane drives that has a gobo wheel.
  List<ChannelCapability> _goboSlots() {
    final rig = LiveRig(
      fixtures: ref.read(patchedFixturesProvider),
      universes: ref.read(universesProvider),
      groups: ref.read(fixtureGroupsProvider),
      stage: ref.read(stagePlanProvider),
    );
    for (final f in targetsOf(widget.lane, rig)) {
      for (final c in f.profile.channels) {
        if (c.function == ChannelFunction.gobo && c.capabilities.isNotEmpty) {
          return [for (final cap in c.capabilities) if (cap.kind != CapabilityKind.range) cap];
        }
      }
    }
    return const [];
  }
}

class _ColorDot extends StatelessWidget {
  final LiveColor color;
  final int index;
  final VoidCallback onTap;
  const _ColorDot({required this.color, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final selected = index >= 0;
    return Semantics(
      button: true,
      selected: selected,
      label: color.label,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.swatch,
            shape: BoxShape.circle,
            border: Border.all(color: selected ? AppColors.accent : AppColors.border, width: selected ? 3 : 1.5),
          ),
          child: selected
              ? Text(
                  '${index + 1}',
                  style: TextStyle(fontWeight: FontWeight.w900, color: color.r + color.g + color.b > 380 ? Colors.black : Colors.white),
                )
              : null,
        ),
      ),
    );
  }
}
