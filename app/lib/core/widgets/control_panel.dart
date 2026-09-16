import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/smart_program.dart';
import '../../state/audio_providers.dart';
import '../../state/momentary_fx_providers.dart';
import '../../state/playback_providers.dart';
import '../../state/smart_program_providers.dart';
import '../../state/tempo_providers.dart';
import '../audio/beat_detector.dart';
import '../audio/tempo_estimator.dart';
import '../playback/chase_player.dart';
import '../playback/smart_program_player.dart';
import '../remote/trigger_actions.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'beat_meter.dart';
import 'log_scale.dart';
import 'momentary_fx_buttons.dart';

/// Everything that used to be the Dashboard's "Tempo & Chase Speed" card,
/// in one narrow column that the control dock can slide open over any tab.
///
/// It lives here rather than on the Dashboard because that's not where it's
/// needed: you reach for the tempo while a bank is running and you're
/// looking at the Banks page. Having one copy also ends the drift — the
/// Banks tab used to carry its own Hold/Fade sliders that quietly disagreed
/// with these.
class ControlPanel extends ConsumerStatefulWidget {
  const ControlPanel({super.key});

  @override
  ConsumerState<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends ConsumerState<ControlPanel> {
  final List<DateTime> _taps = [];
  late final TextEditingController _bpmController;
  bool _useBpm = false;
  double _sensitivity = 0.6;
  BeatFrequencyBand _frequencyBand = BeatFrequencyBand.overall;
  BeatAdaptSpeed _adaptSpeed = BeatAdaptSpeed.normal;

  @override
  void initState() {
    super.initState();
    _bpmController = TextEditingController(text: ref.read(tempoProvider).bpm.round().toString());
    final beatService = ref.read(beatDetectorProvider);
    _sensitivity = beatService.sensitivity;
    _frequencyBand = beatService.frequencyBand;
    _adaptSpeed = beatService.adaptSpeed;
  }

  @override
  void dispose() {
    _bpmController.dispose();
    super.dispose();
  }

  SmartProgramPlayer get _smartPlayer => ref.read(smartProgramPlayerProvider);

  SmartProgram? get _runningProgram {
    final id = _smartPlayer.activeProgramId;
    if (id == null) return null;
    final matches = ref.read(smartProgramsProvider).where((p) => p.id == id);
    return matches.isEmpty ? null : matches.first;
  }

  SmartProgramZone get _runningZone =>
      ref.read(smartProgramStatusProvider).valueOrNull?.zone ?? SmartProgramZone.base;

  double _runningZoneFadeSeconds() {
    final program = _runningProgram;
    if (program == null) return ref.read(tempoProvider).fadeSeconds;
    final fade = switch (_runningZone) {
      SmartProgramZone.faster => program.fasterFade,
      SmartProgramZone.slower => program.slowerFade,
      SmartProgramZone.base => program.baseFade,
    };
    return fade.inMilliseconds / 1000;
  }

  /// Writes a fade back onto the running program's current zone, live.
  void _setRunningZoneFade(double seconds) {
    final program = _runningProgram;
    if (program == null) return;
    final fade = Duration(milliseconds: (seconds * 1000).round());
    final updated = switch (_runningZone) {
      SmartProgramZone.faster => program.copyWith(fasterFade: fade),
      SmartProgramZone.slower => program.copyWith(slowerFade: fade),
      SmartProgramZone.base => program.copyWith(baseFade: fade),
    };
    ref.read(smartProgramsProvider.notifier).upsert(updated);
    syncRunningSmartProgram(ref.read);
    setState(() {});
  }

  void _onTap() {
    final now = DateTime.now();
    if (_taps.isNotEmpty && now.difference(_taps.last) > const Duration(seconds: 2)) {
      _taps.clear();
    }
    _taps.add(now);
    if (_taps.length > 8) _taps.removeAt(0);

    // Two taps is only "the gap between these two" — nothing to check it
    // against. From three on the estimator can discard a mistimed one.
    if (_taps.length == 2) {
      final ms = _taps[1].difference(_taps[0]).inMilliseconds;
      if (ms > 0) _setBpm(60000 / ms, updateController: true);
      return;
    }
    final estimate = estimateTempo(_taps);
    if (estimate != null) _setBpm(estimate.bpm, updateController: true);
  }

  void _setBpm(double bpm, {required bool updateController}) {
    ref.read(tempoProvider.notifier).setBpm(bpm);
    if (updateController) _bpmController.text = ref.read(tempoProvider).bpm.round().toString();
    // With beat sync armed the beats drive the steps, so a new reading
    // changes nothing about playback — restarting here would kick a running
    // chase back to step 1 on every single beat.
    if (ref.read(beatSyncEnabledProvider)) return;
    restartActiveTrigger(ref.read);
  }

  Future<void> _setBeatSync(bool value) async {
    final beatService = ref.read(beatDetectorProvider);
    if (value) {
      beatService.sensitivity = _sensitivity;
      beatService.frequencyBand = _frequencyBand;
      beatService.adaptSpeed = _adaptSpeed;
    }
    final error = await ref.read(beatSyncEnabledProvider.notifier).setEnabled(value);
    if (error != null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    await restartActiveTrigger(ref.read);
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 2),
    child: Text(text, style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
  );

  Widget _readout(String text) => Align(
    alignment: Alignment.centerRight,
    child: Text(text, style: appMonoStyle(fontSize: 11, color: AppColors.textDim)),
  );

  @override
  Widget build(BuildContext context) {
    final tempo = ref.watch(tempoProvider);
    final beatSync = ref.watch(beatSyncEnabledProvider);
    final beatRate = ref.watch(beatRateProvider);
    final smartActive = _smartPlayer.isRunning;
    final flashActive = beatSync && beatRate == BeatRate.flash;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton(
              onPressed: _onTap,
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                side: const BorderSide(color: AppColors.accent, width: 1.5),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'TAP',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accent,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(tempo.bpm.round().toString(), style: appMonoStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    smartActive
                        ? 'Step speed — the program follows the music'
                        : beatSync
                            ? 'Step speed — synced to the beat'
                            : tempo.overrideTiming
                                ? 'Step speed — banks and chases'
                                : 'Step speed — banks only',
                    style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
                  ),
                  if (!beatSync && !smartActive)
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Sec')),
                        ButtonSegment(value: true, label: Text('BPM')),
                      ],
                      selected: {_useBpm},
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onSelectionChanged: (s) => setState(() => _useBpm = s.first),
                    ),
                ],
              ),
            ),
          ],
        ),

        if (_useBpm && !beatSync && !smartActive)
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: () => _setBpm(tempo.bpm - 1, updateController: true),
              ),
              Expanded(
                child: TextField(
                  controller: _bpmController,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  style: appMonoStyle(fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(isDense: true, suffixText: 'BPM'),
                  onChanged: (text) {
                    final value = double.tryParse(text);
                    if (value != null) _setBpm(value, updateController: false);
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: () => _setBpm(tempo.bpm + 1, updateController: true),
              ),
            ],
          )
        else
          // Logarithmic and inverted: up is faster, and the quick end gets
          // real travel instead of the last few pixels.
          Slider(
            value: stepSpeedScale.positionOf(tempo.stepSeconds),
            onChanged: (beatSync || smartActive)
                ? null
                : (p) => ref.read(tempoProvider.notifier).setStepSeconds(stepSpeedScale.valueAt(p)),
            onChangeEnd: (beatSync || smartActive)
                ? null
                : (_) => restartActiveTrigger(ref.read, timingOnly: true),
          ),
        _readout('${tempo.stepSeconds.toStringAsFixed(2)}s / step · ${tempo.bpm.round()} BPM'),

        _label(
          smartActive
              ? 'Fade — the ${_zoneWord()} zone of the running program'
              : flashActive
                  ? 'Fade — off, Flash snaps'
                  : tempo.autoFade
                      ? 'Fade — following the tempo'
                      : 'Fade',
        ),
        Slider(
          value: fadeTimeScale.positionOf(
            smartActive
                ? _runningZoneFadeSeconds()
                : tempo.autoFade
                    ? tempo.effectiveFadeSeconds
                    : tempo.fadeSeconds,
          ),
          activeColor: AppColors.accent2,
          onChanged: (!smartActive && (tempo.autoFade || flashActive))
              ? null
              : (p) {
                  final seconds = fadeTimeScale.valueAt(p);
                  if (smartActive) {
                    _setRunningZoneFade(seconds);
                  } else {
                    ref.read(tempoProvider.notifier).setFadeSeconds(seconds);
                  }
                },
          onChangeEnd: smartActive ? null : (_) => restartActiveTrigger(ref.read, timingOnly: true),
        ),
        _readout(
          '${(smartActive ? _runningZoneFadeSeconds() : tempo.effectiveFadeSeconds).toStringAsFixed(2)}s fade',
        ),

        if (!smartActive) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Auto fade', style: TextStyle(fontSize: 13)),
            subtitle: Text(
              flashActive
                  ? 'Not in play while Flash is the beat rate'
                  : 'Slower music fades longer, faster snaps tighter',
              style: TextStyle(
                fontSize: 10.5,
                color: flashActive ? AppColors.accent : AppColors.textFaint,
              ),
            ),
            value: tempo.autoFade,
            onChanged: (value) => ref.read(tempoProvider.notifier).setAutoFade(value),
          ),
          if (tempo.autoFade) ...[
            Slider(
              value: tempo.autoFadeAmount,
              activeColor: AppColors.accent2,
              onChanged: (v) => ref.read(tempoProvider.notifier).setAutoFadeAmount(v),
            ),
            _readout('Amount ${(tempo.autoFadeAmount * 100).round()}%'),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Override saved timing', style: TextStyle(fontSize: 13)),
            subtitle: Text(
              tempo.overrideTiming
                  ? 'Chases run at the timing set here'
                  : 'Chases keep their own; banks always follow this',
              style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint),
            ),
            value: tempo.overrideTiming,
            onChanged: (value) {
              ref.read(tempoProvider.notifier).setOverrideTiming(value);
              restartActiveTrigger(ref.read);
            },
          ),
        ],

        // No grand master here: the panel never shows without the dock's
        // rail beside it, and that carries the fader.
        const Divider(height: 22),

        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          secondary: const Icon(Icons.mic_none, size: 18, color: AppColors.textDim),
          title: const Text('Beat sync', style: TextStyle(fontSize: 13)),
          value: beatSync,
          onChanged: _setBeatSync,
        ),

        if (beatSync) ...[
          _label('Steps per beat'),
          SegmentedButton<BeatRate>(
            segments: [
              for (final rate in BeatRate.values) ButtonSegment(value: rate, label: Text(rate.label)),
            ],
            selected: {beatRate},
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onSelectionChanged: (s) => ref.read(beatRateProvider.notifier).state = s.first,
          ),
          if (flashActive) ...[
            _label('Flash length'),
            Slider(
              value: ref.watch(flashLengthProvider).inMilliseconds.toDouble(),
              min: 20,
              max: 500,
              activeColor: AppColors.accent2,
              onChanged: (v) =>
                  ref.read(flashLengthProvider.notifier).state = Duration(milliseconds: v.round()),
            ),
            _readout('${ref.watch(flashLengthProvider).inMilliseconds} ms'),
          ],
          const SizedBox(height: 10),
          BeatMeter(service: ref.read(beatDetectorProvider)),
          _label('Sensitivity'),
          Slider(
            value: _sensitivity,
            activeColor: AppColors.accent2,
            onChanged: (value) {
              setState(() => _sensitivity = value);
              ref.read(beatDetectorProvider).sensitivity = value;
            },
          ),
          _label('Baseline memory'),
          SegmentedButton<BeatAdaptSpeed>(
            segments: [
              for (final speed in BeatAdaptSpeed.values)
                ButtonSegment(value: speed, label: Text(speed.label)),
            ],
            selected: {_adaptSpeed},
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onSelectionChanged: (s) {
              setState(() => _adaptSpeed = s.first);
              ref.read(beatDetectorProvider).adaptSpeed = s.first;
            },
          ),
          _label('React to'),
          SegmentedButton<BeatFrequencyBand>(
            segments: [
              for (final band in BeatFrequencyBand.values)
                ButtonSegment(value: band, label: Text(band.label)),
            ],
            selected: {_frequencyBand},
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onSelectionChanged: (s) {
              setState(() => _frequencyBand = s.first);
              ref.read(beatDetectorProvider).frequencyBand = s.first;
            },
          ),
        ],

        // Last, and deliberately: the momentary buttons are a copy, not the
        // place you reach for them. They live on the dock's strip, which
        // gives them up on a narrow screen — this is where they come back,
        // so nothing is ever only on the strip. The open dock's rail leaves
        // them out entirely: three more tiles down it would push Blackout
        // off the bottom of a phone held sideways.
        const Divider(height: 22),
        _label('Momentary — hold one, let go to drop back'),
        Row(
          children: [
            for (final entry in momentaryFxStyles.entries) ...[
              MomentaryFxButton(fx: entry.key, icon: entry.value.icon, color: entry.value.color),
              const SizedBox(width: 8),
            ],
          ],
        ),
        _label('Strobe rate'),
        Slider(
          value: ref.watch(strobeRateProvider).clamp(minStrobeHz, maxStrobeHz),
          min: minStrobeHz,
          max: maxStrobeHz,
          activeColor: AppColors.accent,
          onChanged: (value) => ref.read(strobeRateProvider.notifier).state = value,
        ),
        _readout('${ref.watch(strobeRateProvider).toStringAsFixed(1)} flashes a second'),
      ],
    );
  }

  String _zoneWord() => switch (_runningZone) {
    SmartProgramZone.faster => 'faster',
    SmartProgramZone.slower => 'slower',
    SmartProgramZone.base => 'base',
  };
}
