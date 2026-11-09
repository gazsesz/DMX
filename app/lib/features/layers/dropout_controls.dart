import 'package:flutter/material.dart';

import '../../core/playback/dimmer_dropout.dart';
import '../../core/theme/app_colors.dart';
import '../../models/layer.dart';
import '../../models/patched_fixture.dart';
import '../../l10n/l10n.dart';

/// The dimmer dropout's settings, edited in place: which layers (and
/// optionally lamps) it cuts, how long the dark lasts, and whether it comes on
/// a timer or on the beat. Shared by the Layers screen, the Smart Program
/// editor and the Chase editor, which differ only in where the settings are
/// kept.
class DropoutControls extends StatelessWidget {
  final DropoutSettings settings;
  final ValueChanged<DropoutSettings> onChanged;

  /// The layers offered as targets, or null to leave the layer choice out (a
  /// chase always cuts the layer it plays on). A selection that names a layer
  /// not in this list — one deleted since — is shown as if it weren't there.
  final List<Layer>? layers;

  /// Lamps offered as targets; null leaves the lamp choice out.
  final List<PatchedFixture>? fixtures;

  const DropoutControls({
    super.key,
    required this.settings,
    required this.onChanged,
    this.layers,
    this.fixtures,
  });

  @override
  Widget build(BuildContext context) {
    final layerList = layers;
    final lamps = fixtures;
    final liveTargets = {
      for (final l in layerList ?? const <Layer>[])
        if (settings.targetLayerIds.contains(l.id)) l.id,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (layerList != null) ...[
          _Label(context.l10n.dropoutWhichLayer),
          Wrap(
            spacing: 6,
            children: [
              ChoiceChip(
                label: Text(context.l10n.commonAll),
                selected: liveTargets.isEmpty,
                onSelected: (_) => onChanged(settings.copyWith(targetLayerIds: const {})),
              ),
              for (final layer in layerList)
                FilterChip(
                  label: Text(layer.name),
                  selected: liveTargets.contains(layer.id),
                  onSelected: (on) => onChanged(
                    settings.copyWith(
                      targetLayerIds: {
                        for (final id in liveTargets)
                          if (id != layer.id) id,
                        if (on) layer.id,
                      },
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (lamps != null && lamps.isNotEmpty) ...[
          _Label(context.l10n.dropoutWhichFixtures),
          Wrap(
            spacing: 6,
            children: [
              ChoiceChip(
                label: Text(context.l10n.commonAll),
                selected: settings.fixtureIds.isEmpty,
                onSelected: (_) => onChanged(settings.copyWith(fixtureIds: {})),
              ),
              for (final fixture in lamps)
                FilterChip(
                  label: Text(fixture.label),
                  selected: settings.fixtureIds.contains(fixture.id),
                  onSelected: (on) => onChanged(
                    settings.copyWith(
                      fixtureIds: {
                        for (final id in settings.fixtureIds)
                          if (id != fixture.id) id,
                        if (on) fixture.id,
                      },
                    ),
                  ),
                ),
            ],
          ),
        ],
        _Label(context.l10n.dropoutWhen),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, label: Text(context.l10n.dropoutAtIntervals)),
            ButtonSegment(value: true, label: Text(context.l10n.dropoutOnBeat)),
          ],
          selected: {settings.onBeat},
          onSelectionChanged: (s) => onChanged(settings.copyWith(onBeat: s.first)),
        ),
        if (settings.onBeat) ...[
          _Label(context.l10n.dropoutWhichBeat),
          Wrap(
            spacing: 6,
            children: [
              for (final n in DropoutSettings.beatDivisions)
                ChoiceChip(
                  label: Text(context.l10n.dropoutEveryNthBeat(n)),
                  selected: settings.beatEvery == n,
                  onSelected: (_) => onChanged(settings.copyWith(beatEvery: n)),
                ),
            ],
          ),
          Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              context.l10n.dropoutBeatHint,
              style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
            ),
          ),
        ],
        _SliderRow(
          label: context.l10n.dropoutDarkLength,
          value: settings.lengthMs.toDouble(),
          min: DropoutSettings.minLengthMs.toDouble(),
          max: DropoutSettings.maxLengthMs.toDouble(),
          text: '${settings.lengthMs} ms',
          onChanged: (v) => onChanged(settings.copyWith(lengthMs: v.round())),
        ),
        _SliderRow(
          label: 'Fade out',
          value: settings.fadeOutMs.toDouble(),
          min: 0,
          max: DropoutSettings.maxFadeOutMs.toDouble(),
          text: settings.fadeOutMs == 0 ? context.l10n.dropoutInstant : '${settings.fadeOutMs} ms',
          onChanged: (v) => onChanged(settings.copyWith(fadeOutMs: v.round())),
        ),
        _SliderRow(
          label: 'Fade in',
          value: settings.fadeInMs.toDouble(),
          min: 0,
          max: DropoutSettings.maxFadeInMs.toDouble(),
          text: settings.fadeInMs == 0 ? context.l10n.dropoutInstant : '${settings.fadeInMs} ms',
          onChanged: (v) => onChanged(settings.copyWith(fadeInMs: v.round())),
        ),
        _SliderRow(
          label: settings.onBeat ? context.l10n.dropoutGapNoBeat : context.l10n.dropoutAverageGap,
          value: settings.intervalMs.toDouble(),
          min: DropoutSettings.minIntervalMs.toDouble(),
          max: DropoutSettings.maxIntervalMs.toDouble(),
          text: '${(settings.intervalMs / 1000).toStringAsFixed(1)} s',
          onChanged: (v) => onChanged(settings.copyWith(intervalMs: v.round())),
        ),
        if (!settings.onBeat)
          _SliderRow(
            label: context.l10n.dropoutIrregularity,
            value: settings.jitter,
            min: 0,
            max: 1,
            text: '${(settings.jitter * 100).round()}%',
            onChanged: (v) => onChanged(settings.copyWith(jitter: v)),
          ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
  );
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String text;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.text,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 110, child: Text(label, style: const TextStyle(fontSize: 12))),
      Expanded(child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged)),
      SizedBox(width: 56, child: Text(text, textAlign: TextAlign.end, style: const TextStyle(fontSize: 12))),
    ],
  );
}
