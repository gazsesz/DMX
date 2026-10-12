import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/movement/movement_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/log_scale.dart';
import '../../core/widgets/pan_tilt_pad.dart';
import '../../models/bank.dart';
import '../../models/group_position.dart';
import '../../models/movement_fx.dart';
import '../../state/bank_providers.dart';
import '../../state/fixture_group_providers.dart';
import '../../state/fixture_providers.dart';

const _lapScale = LogScale(min: 0.5, max: 60.0, inverted: true);

/// The editor for a Movement FX bank: pick the path, size it, set its speed
/// and say which heads move. Every change goes straight to the bank, and a
/// running bank follows it on the next tick — nothing needs restarting.
class MovementFxEditor extends ConsumerWidget {
  final Bank bank;

  const MovementFxEditor({super.key, required this.bank});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fx = bank.fx;
    if (fx == null) return const SizedBox.shrink();
    final groups = ref.watch(fixtureGroupsProvider);
    final fixtures = ref.watch(patchedFixturesProvider);
    final movers = movementHeads(
      const MovementFx(),
      fixtures,
      const [],
    ).map((h) => h.fixture).toList();
    void update(MovementFx next) =>
        ref.read(banksProvider.notifier).setFx(bank.id, next);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label('Shape'),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final shape in MovementShape.values)
                ChoiceChip(
                  label: Text(shape.label),
                  selected: fx.shape == shape,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => update(fx.copyWith(shape: shape)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(height: 110, child: _PathPreview(fx: fx)),
          const SizedBox(height: 8),
          _label('Speed'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Lock to the beat'),
            subtitle: Text(
              fx.beatLocked
                  ? 'One lap every ${_beats(fx.beats)} beats; without a beat it carries on at the last tempo'
                  : 'Free running at its own pace',
              style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
            ),
            value: fx.beatLocked,
            onChanged: (v) => update(fx.copyWith(beatLocked: v)),
          ),
          if (fx.beatLocked)
            Wrap(
              spacing: 8,
              children: [
                for (final beats in MovementFx.beatChoices)
                  ChoiceChip(
                    label: Text('${_beats(beats)} beats'),
                    selected: fx.beats == beats,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => update(fx.copyWith(beats: beats)),
                  ),
              ],
            )
          else
            _slider(
              'Lap time',
              _lapScale.positionOf(fx.periodSec),
              '${fx.periodSec.toStringAsFixed(fx.periodSec < 10 ? 1 : 0)} s',
              // Right is faster, as on the dock's step speed.
              (v) => update(
                fx.copyWith(
                  periodSec: double.parse(
                    _lapScale.valueAt(v).toStringAsFixed(2),
                  ),
                ),
              ),
              min: 0,
              max: 1,
            ),
          Wrap(
            spacing: 16,
            children: [
              _toggle(
                'Reverse',
                fx.reverse,
                (v) => update(fx.copyWith(reverse: v)),
              ),
              _toggle(
                'Mirror left/right',
                fx.mirror,
                (v) => update(fx.copyWith(mirror: v)),
              ),
            ],
          ),
          _slider(
            'Wave across heads',
            fx.phaseSpread,
            fx.phaseSpread == 0
                ? 'together'
                : '${(fx.phaseSpread * 100).round()}% of a lap',
            (v) => update(fx.copyWith(phaseSpread: v)),
          ),
          const SizedBox(height: 4),
          _label('Path'),
          SegmentedButton<MovementSpace>(
            segments: [
              for (final space in MovementSpace.values)
                ButtonSegment(value: space, label: Text(space.label)),
            ],
            selected: {fx.space},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) => update(fx.copyWith(space: s.first)),
          ),
          const SizedBox(height: 4),
          if (fx.space == MovementSpace.panTilt) ...[
            _slider(
              'Width',
              fx.sizePanDeg / 180,
              '±${fx.sizePanDeg.round()}°',
              (v) => update(fx.copyWith(sizePanDeg: v * 180)),
            ),
            _slider(
              'Height',
              fx.sizeTiltDeg / 90,
              '±${fx.sizeTiltDeg.round()}°',
              (v) => update(fx.copyWith(sizeTiltDeg: v * 90)),
            ),
            _label('Centre'),
            Center(
              child: SizedBox(
                width: 220,
                height: 150,
                child: PanTiltPad(
                  value: fx.center,
                  panRangeDeg: 540,
                  tiltRangeDeg: 270,
                  onChanged: (v) => update(fx.copyWith(center: v)),
                ),
              ),
            ),
          ] else ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                'Drawn on the stage plan, so every head aims at its own point of the shape.',
                style: TextStyle(fontSize: 11, color: AppColors.textFaint),
              ),
            ),
            _slider(
              'Width',
              fx.sizeXM / 10,
              '±${fx.sizeXM.toStringAsFixed(1)} m',
              (v) => update(fx.copyWith(sizeXM: v * 10)),
            ),
            _slider(
              'Depth',
              fx.sizeYM / 10,
              '±${fx.sizeYM.toStringAsFixed(1)} m',
              (v) => update(fx.copyWith(sizeYM: v * 10)),
            ),
            _slider(
              'Centre across',
              fx.stageCenter.x,
              '${(fx.stageCenter.x * 100).round()}%',
              (v) => update(
                fx.copyWith(stageCenter: StagePoint(v, fx.stageCenter.y)),
              ),
            ),
            _slider(
              'Centre depth',
              fx.stageCenter.y,
              '${(fx.stageCenter.y * 100).round()}%',
              (v) => update(
                fx.copyWith(stageCenter: StagePoint(fx.stageCenter.x, v)),
              ),
            ),
            _slider(
              'Height of the plane',
              fx.aimHeightM / 5,
              '${fx.aimHeightM.toStringAsFixed(1)} m',
              (v) => update(fx.copyWith(aimHeightM: v * 5)),
            ),
          ],
          _slider(
            'Rotate',
            (fx.rotationDeg + 180) / 360,
            '${fx.rotationDeg.round()}°',
            (v) => update(
              fx.copyWith(rotationDeg: (v * 360 - 180).roundToDouble()),
            ),
          ),
          const SizedBox(height: 4),
          _label('Heads'),
          Text(
            fx.groupIds.isEmpty && fx.fixtureIds.isEmpty
                ? 'Every moving head (${movers.length})'
                : 'Only the ones picked below',
            style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final group in groups)
                FilterChip(
                  avatar: const Icon(Icons.folder_outlined, size: 14),
                  label: Text(group.name),
                  selected: fx.groupIds.contains(group.id),
                  visualDensity: VisualDensity.compact,
                  onSelected: (on) => update(
                    fx.copyWith(groupIds: _toggled(fx.groupIds, group.id, on)),
                  ),
                ),
              for (final fixture in movers)
                FilterChip(
                  label: Text(fixture.label),
                  selected: fx.fixtureIds.contains(fixture.id),
                  visualDensity: VisualDensity.compact,
                  onSelected: (on) => update(
                    fx.copyWith(
                      fixtureIds: _toggled(fx.fixtureIds, fixture.id, on),
                    ),
                  ),
                ),
            ],
          ),
          if (movers.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'No moving heads in the patch (a fixture needs pan and tilt channels).',
                style: TextStyle(fontSize: 11, color: AppColors.accent),
              ),
            ),
        ],
      ),
    );
  }

  static Set<String> _toggled(Set<String> ids, String id, bool on) =>
      on ? {...ids, id} : ids.difference({id});

  static String _beats(double beats) => beats == beats.roundToDouble()
      ? beats.round().toString()
      : beats.toString();

  static Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 2),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 10.5,
        letterSpacing: 1,
        color: AppColors.textFaint,
      ),
    ),
  );

  static Widget _toggle(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Switch(value: value, onChanged: onChanged),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );

  static Widget _slider(
    String label,
    double value,
    String readout,
    ValueChanged<double> onChanged, {
    double min = 0,
    double max = 1,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 118,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textFaint),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 78,
          child: Text(
            readout,
            style: appMonoStyle(fontSize: 10.5, color: AppColors.textFaint),
          ),
        ),
      ],
    );
  }
}

/// The shape as drawn, sized and rotated as the effect has it — the arrow
/// marks which way it runs.
class _PathPreview extends StatelessWidget {
  final MovementFx fx;

  const _PathPreview({required this.fx});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _PathPainter(fx), size: Size.infinite);
}

class _PathPainter extends CustomPainter {
  final MovementFx fx;

  _PathPainter(this.fx);

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Paint()
      ..color = AppColors.textFaint.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      frame,
    );

    // Scale the drawing so the path fills the box whatever its size.
    final sx = fx.space == MovementSpace.stage ? fx.sizeXM : fx.sizePanDeg;
    final sy = fx.space == MovementSpace.stage ? fx.sizeYM : fx.sizeTiltDeg;
    final r = fx.rotationDeg * math.pi / 180;
    Offset point(double phase) {
      final (x, y) = shapeAt(fx.shape, fx.reverse ? -phase : phase);
      final dx = x * sx;
      final dy = y * sy;
      return Offset(
        dx * math.cos(r) - dy * math.sin(r),
        dx * math.sin(r) + dy * math.cos(r),
      );
    }

    const steps = 120;
    final points = [for (var i = 0; i <= steps; i++) point(i / steps)];
    final extent = points.fold<double>(
      1e-6,
      (m, p) => math.max(m, math.max(p.dx.abs(), p.dy.abs())),
    );
    final scale = (math.min(size.width, size.height) / 2 - 10) / extent;
    final centre = size.center(Offset.zero);
    Offset toCanvas(Offset p) => centre + Offset(p.dx * scale, p.dy * scale);

    final path = Path()
      ..moveTo(toCanvas(points.first).dx, toCanvas(points.first).dy);
    for (final p in points.skip(1)) {
      final c = toCanvas(p);
      path.lineTo(c.dx, c.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.accent2
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      toCanvas(points.first),
      4,
      Paint()..color = AppColors.accent,
    );
  }

  @override
  bool shouldRepaint(_PathPainter old) => old.fx != fx;
}
