import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/movement_fx.dart';
import '../../state/movement_live_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'log_scale.dart';

const _speedScale = LogScale(min: 0.25, max: 4.0);

/// The Movement strip: four live knobs over whatever Movement FX is running.
///
/// Size and Speed scale the bank's own settings, Shift adds to its wave
/// across the heads and Smooth rounds the move off. None of them changes the
/// bank, and a double tap on a label puts that one back to neutral.
class MovementLiveBar extends ConsumerWidget {
  const MovementLiveBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(movementLiveProvider);
    final notifier = ref.read(movementLiveProvider.notifier);

    final knobs = [
      _Knob(
        label: 'Size',
        readout: '${(live.size * 100).round()}%',
        value: live.size / MovementLive.sizeRange.max,
        changed: live.size != 1,
        onChanged: (v) => notifier.set(size: v * MovementLive.sizeRange.max),
        onReset: () => notifier.set(size: 1),
      ),
      _Knob(
        label: 'Speed',
        readout: '×${live.speed.toStringAsFixed(live.speed < 1 ? 2 : 1)}',
        value: _speedScale.positionOf(live.speed),
        changed: live.speed != 1,
        onChanged: (v) => notifier.set(speed: _speedScale.valueAt(v)),
        onReset: () => notifier.set(speed: 1),
      ),
      _Knob(
        label: 'Shift',
        readout: live.shift == 0 ? 'off' : '+${(live.shift * 100).round()}%',
        value: live.shift,
        changed: live.shift != 0,
        onChanged: (v) => notifier.set(shift: v),
        onReset: () => notifier.set(shift: 0),
      ),
      _Knob(
        label: 'Smooth',
        readout: live.smooth == 0 ? 'off' : '${(live.smooth * 1.5).toStringAsFixed(1)} s',
        value: live.smooth,
        changed: live.smooth != 0,
        onChanged: (v) => notifier.set(smooth: v),
        onReset: () => notifier.set(smooth: 0),
      ),
    ];

    return Material(
      color: AppColors.panel2,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Four across where there's room; two rows of two on a phone.
            final narrow = constraints.maxWidth < 620;
            final reset = IconButton(
              tooltip: 'Reset the Movement knobs',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.restart_alt, size: 20, color: live.isNeutral ? AppColors.textFaint : AppColors.accent),
              onPressed: live.isNeutral ? null : notifier.reset,
            );
            return Row(
              children: [
                const Tooltip(
                  message: 'Movement FX — live knobs',
                  child: Icon(Icons.open_with, size: 16, color: AppColors.accent2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: narrow
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(children: [for (final k in knobs.take(2)) Expanded(child: k)]),
                            Row(children: [for (final k in knobs.skip(2)) Expanded(child: k)]),
                          ],
                        )
                      : Row(children: [for (final k in knobs) Expanded(child: k)]),
                ),
                reset,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Knob extends StatelessWidget {
  final String label;
  final String readout;
  final double value;
  final bool changed;
  final ValueChanged<double> onChanged;
  final VoidCallback onReset;

  const _Knob({
    required this.label,
    required this.readout,
    required this.value,
    required this.changed,
    required this.onChanged,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        children: [
          GestureDetector(
            onDoubleTap: onReset,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 50,
              child: Text(
                label,
                style: TextStyle(fontSize: 11.5, color: changed ? AppColors.accent : AppColors.textFaint),
              ),
            ),
          ),
          Expanded(child: Slider(value: value.clamp(0.0, 1.0), onChanged: onChanged)),
          SizedBox(width: 44, child: Text(readout, style: appMonoStyle(fontSize: 10.5, color: AppColors.textFaint))),
        ],
      ),
    );
  }
}
