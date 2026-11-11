import 'package:flutter/material.dart';

import '../../state/audio_providers.dart';
import '../audio/beat_detector.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../../l10n/l10n.dart';

/// The "below this loudness is silence" line for the microphone — see
/// [BeatDetectorService.silenceFloorDb]. Shown next to Sensitivity, under
/// the [BeatMeter] whose Level bar draws the same line in red, so it can be
/// set by eye: play nothing, then music, and put it between the two.
class SilenceFloorSlider extends StatefulWidget {
  final BeatDetectorService service;

  const SilenceFloorSlider({super.key, required this.service});

  @override
  State<SilenceFloorSlider> createState() => _SilenceFloorSliderState();
}

class _SilenceFloorSliderState extends State<SilenceFloorSlider> {
  late double _value = widget.service.silenceFloorDb
      .clamp(BeatDetectorService.silenceFloorOff, BeatDetectorService.silenceFloorMax)
      .toDouble();

  bool get _off => _value <= BeatDetectorService.silenceFloorOff;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(context.l10n.wSilenceFloor, style: TextStyle(fontSize: 11, color: AppColors.textFaint)),
              ),
              Text(
                _off ? context.l10n.wOff : context.l10n.wDb(_value.round()),
                style: appMonoStyle(fontSize: 11, color: _off ? AppColors.textFaint : AppColors.danger),
              ),
            ],
          ),
        ),
        Slider(
          key: const Key('silence-floor-slider'),
          value: _value,
          min: BeatDetectorService.silenceFloorOff,
          max: BeatDetectorService.silenceFloorMax,
          divisions: 80,
          activeColor: AppColors.danger,
          onChanged: (v) {
            setState(() => _value = v);
            setSilenceFloor(widget.service, v);
          },
        ),
        Text(
          context.l10n.wLoudnessTheLevelBar,
          style: TextStyle(fontSize: 9.5, color: AppColors.textFaint),
        ),
      ],
    );
  }
}
