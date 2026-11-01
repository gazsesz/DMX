import 'package:flutter/material.dart';

import '../../state/audio_providers.dart';
import '../audio/beat_detector.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// The manual "below this is silence" line for the microphone — see
/// [BeatDetectorService.silenceFloorDb]. Shown next to Sensitivity, under
/// the [BeatMeter] that draws the same line in red, so it can be set by
/// eye: play nothing, tap the keyboard, and pull it above the peaks.
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
              const Expanded(
                child: Text('Silence floor', style: TextStyle(fontSize: 11, color: AppColors.textFaint)),
              ),
              Text(
                _off ? 'Off' : '${_value.round()} dB',
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
          divisions: 100,
          activeColor: AppColors.danger,
          onChanged: (v) {
            setState(() => _value = v);
            setSilenceFloor(widget.service, v);
          },
        ),
        const Text(
          'Anything quieter is silence: no beat, so a Smart Program blacks out. '
          'Set it above the room (keyboard, talking) and below the music.',
          style: TextStyle(fontSize: 9.5, color: AppColors.textFaint),
        ),
      ],
    );
  }
}
