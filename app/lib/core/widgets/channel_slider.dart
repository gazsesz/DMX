import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A labeled 0-255 DMX channel slider with a live numeric readout, shared
/// by the Scene editor and Manual Control screens.
class ChannelSliderTile extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final ValueChanged<int> onChanged;

  const ChannelSliderTile({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(activeTrackColor: color, thumbColor: color),
              child: Slider(
                value: value.toDouble(),
                min: 0,
                max: 255,
                onChanged: (v) => onChanged(v.round()),
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$value',
              textAlign: TextAlign.end,
              style: appMonoStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
