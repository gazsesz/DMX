import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/beat_detector.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Live microphone level + beat LED, so the user can see the mic is actually
/// picking up sound and where the current sensitivity threshold sits.
///
/// The bar is windowed *relative to the rolling ambient average* (not an
/// absolute dB scale) so the sensitivity threshold visibly moves as the
/// slider changes, regardless of how loud/quiet the room is.
class BeatMeter extends StatefulWidget {
  final BeatDetectorService service;

  const BeatMeter({super.key, required this.service});

  @override
  State<BeatMeter> createState() => _BeatMeterState();
}

class _BeatMeterState extends State<BeatMeter> {
  static const _lowOffset = -5.0; // dB below ambient shown at the left edge
  static const _highOffset = 20.0; // dB above ambient shown at the right edge

  StreamSubscription<BeatMeterSample>? _sub;
  double _db = -160;
  double _avg = -160;
  double _requiredRise = 6;
  DateTime? _lastBeatAt;

  @override
  void initState() {
    super.initState();
    _sub = widget.service.meterStream.listen((sample) {
      if (!mounted) return;
      setState(() {
        _db = sample.db;
        _avg = sample.avg;
        _requiredRise = sample.requiredRise;
        if (sample.isBeat) _lastBeatAt = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  double _normalize(double value) {
    final low = _avg + _lowOffset;
    final high = _avg + _highOffset;
    if (high - low <= 0) return 0;
    return ((value - low) / (high - low)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final level = _normalize(_db);
    final thresholdX = _normalize(_avg + _requiredRise);
    final recentBeat = _lastBeatAt != null &&
        DateTime.now().difference(_lastBeatAt!) < const Duration(milliseconds: 180);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: recentBeat ? AppColors.accent : AppColors.panel2,
                border: Border.all(color: recentBeat ? AppColors.accent : AppColors.border, width: 1.5),
                boxShadow: recentBeat
                    ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.6), blurRadius: 8, spreadRadius: 1)]
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 14,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(color: AppColors.panel2, borderRadius: BorderRadius.circular(4)),
                        ),
                        FractionallySizedBox(
                          widthFactor: level,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [AppColors.accent2, AppColors.accent]),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 150),
                          left: (thresholdX * constraints.maxWidth - 1).clamp(0.0, constraints.maxWidth - 2),
                          top: 0,
                          bottom: 0,
                          child: Container(width: 2, color: Colors.white70),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Needs +${_requiredRise.toStringAsFixed(1)}dB above ambient to trigger',
          style: appMonoStyle(fontSize: 9.5, color: AppColors.textFaint),
        ),
      ],
    );
  }
}
