import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/beat_detector.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Live microphone levels — one bar per frequency band, with the band
/// detection is actually following marked as active.
///
/// Showing every band rather than only the selected one is the point: when
/// the beat isn't being picked up, the useful question is "which band *is*
/// the beat in?", and one bar can't answer it. With all five drawn you can
/// see the kick pumping while the mids sit flat, and switch to it knowing
/// why.
///
/// Each bar is windowed *relative to that band's own rolling average* (not
/// an absolute dB scale), so a quiet band still reads usefully and the
/// sensitivity threshold visibly moves as the slider changes.
class BeatMeter extends StatefulWidget {
  final BeatDetectorService service;

  const BeatMeter({super.key, required this.service});

  @override
  State<BeatMeter> createState() => _BeatMeterState();
}

class _BeatMeterState extends State<BeatMeter> {
  static const _lowOffset = -5.0; // dB below a band's average at the left edge
  static const _highOffset = 28.0; // dB above it at the right edge

  StreamSubscription<BeatMeterSample>? _sub;
  BeatMeterSample? _sample;
  DateTime? _lastBeatAt;

  @override
  void initState() {
    super.initState();
    _sub = widget.service.meterStream.listen((sample) {
      if (!mounted) return;
      setState(() {
        _sample = sample;
        if (sample.isBeat) _lastBeatAt = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  static double _normalize(double value, double avg) {
    final low = avg + _lowOffset;
    final high = avg + _highOffset;
    if (high - low <= 0) return 0;
    return ((value - low) / (high - low)).clamp(0.0, 1.0);
  }

  Widget _bandRow(BeatFrequencyBand band, BandLevel? level, {required bool active, required bool recentBeat}) {
    final sample = _sample;
    final fill = level == null ? 0.0 : _normalize(level.db, level.avg);
    // The threshold marker only means anything on the band being watched —
    // it's the line that band has to cross to fire a beat.
    final threshold = active && sample != null && level != null
        ? _normalize(level.avg + sample.requiredRise, level.avg)
        : null;
    final color = active ? AppColors.accent : AppColors.textFaint;

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            child: active
                ? AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: recentBeat ? AppColors.accent : AppColors.panel2,
                      border: Border.all(
                        color: recentBeat ? AppColors.accent : AppColors.border,
                        width: 1.2,
                      ),
                      boxShadow: recentBeat
                          ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.6), blurRadius: 7, spreadRadius: 1)]
                          : null,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 5),
          SizedBox(
            width: 58,
            child: Text(
              band.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                color: active ? AppColors.text : AppColors.textFaint,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SizedBox(
              height: active ? 11 : 7,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.panel2,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: fill,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: active
                                  ? const [AppColors.accent2, AppColors.accent]
                                  : [AppColors.textFaint.withValues(alpha: 0.5), AppColors.textDim],
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      if (threshold != null)
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 150),
                          left: (threshold * constraints.maxWidth - 1).clamp(0.0, constraints.maxWidth - 2),
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
          const SizedBox(width: 6),
          SizedBox(
            width: 26,
            child: Text(
              active ? 'WATCH' : '',
              textAlign: TextAlign.right,
              style: appMonoStyle(fontSize: 7.5, color: color).copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sample = _sample;
    final activeBand = sample?.band ?? widget.service.frequencyBand;
    final recentBeat = _lastBeatAt != null &&
        DateTime.now().difference(_lastBeatAt!) < const Duration(milliseconds: 180);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final band in BeatFrequencyBand.values)
          _bandRow(
            band,
            sample?.bands[band],
            active: band == activeBand,
            recentBeat: recentBeat,
          ),
        const SizedBox(height: 2),
        Text(
          sample == null
              ? 'Waiting for the microphone…'
              : 'Watching ${activeBand.label} · needs +${sample.requiredRise.toStringAsFixed(1)}dB above its average to trigger',
          style: appMonoStyle(fontSize: 9, color: AppColors.textFaint),
        ),
      ],
    );
  }
}
