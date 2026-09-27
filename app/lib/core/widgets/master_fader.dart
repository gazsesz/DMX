import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/artnet_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// The grand master: one fader that takes the whole rig down without
/// touching what's programmed.
///
/// It scales intensity only — dimmer channels, or the colour emitters on a
/// fixture that has no dimmer — so pulling it down dims the stage instead
/// of swinging moving heads around or changing gobos.
///
/// Its own file because the dock draws it in two shapes — along the closed
/// strip and down the open panel's rail — and it's the one control there
/// that isn't a button.
class MasterFader extends ConsumerWidget {
  /// Stacks the label above the fader and the readout below it, for the
  /// narrow rail. Side by side otherwise.
  final bool vertical;

  /// The width the dock lays it out at; the panel lets it fill the column.
  final double? width;

  const MasterFader({super.key, required this.vertical, this.width});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = ref.watch(grandMasterProvider);
    final percent = (level * 100).round();
    final readout = Text(
      '$percent%',
      style: appMonoStyle(
        fontSize: 10.5,
        color: percent == 100 ? AppColors.textDim : AppColors.accent,
      ),
    );
    const label = Text('Master', style: TextStyle(fontSize: 10.5, color: AppColors.textDim));

    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Side by side only where there's room. In the narrow rail the
          // label and the percentage stack, or they overflow.
          if (vertical)
            label
          else
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [label, readout]),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: level,
              activeColor: AppColors.accent,
              onChanged: (value) => ref.read(grandMasterProvider.notifier).set(value),
            ),
          ),
          if (vertical) readout,
        ],
      ),
    );
  }
}
