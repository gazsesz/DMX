import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../state/dimmer_dropout_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/layer_providers.dart';

/// The dimmer dropout's controls: which layers and fixtures it cuts, how long
/// the dark lasts and how often it comes. It sits on the Layers screen because
/// its target is a layer — it cuts what that layer is lighting, not the rig.
class DimmerDropoutCard extends ConsumerWidget {
  const DimmerDropoutCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(dimmerDropoutProvider);
    final controller = ref.read(dimmerDropoutProvider.notifier);
    final layers = ref.watch(layersProvider);
    final fixtures = ref.watch(patchedFixturesProvider);

    // A layer that was deleted while targeted would leave a dropout aimed at
    // nothing; show only the ones that still exist.
    final liveTargets = {
      for (final l in layers)
        if (settings.targetLayerIds.contains(l.id)) l.id,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Dimmer-bevágás', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text(
                'Időnként egy pillanatra sötét, a többi (pásztázás, szín) közben megy tovább',
                style: TextStyle(fontSize: 11, color: AppColors.textFaint),
              ),
              value: settings.enabled,
              onChanged: (on) => controller.update(settings.copyWith(enabled: on, targetLayerIds: liveTargets)),
            ),
            const _Label('Melyik rétegre'),
            Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('Mind'),
                  selected: liveTargets.isEmpty,
                  onSelected: (_) => controller.update(settings.copyWith(targetLayerIds: const {})),
                ),
                for (final layer in layers)
                  FilterChip(
                    label: Text(layer.name),
                    selected: liveTargets.contains(layer.id),
                    onSelected: (on) => controller.update(
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
            if (fixtures.isNotEmpty) ...[
              const _Label('Melyik lámpákra'),
              Wrap(
                spacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Mind'),
                    selected: settings.fixtureIds.isEmpty,
                    onSelected: (_) => controller.update(settings.copyWith(fixtureIds: const {})),
                  ),
                  for (final fixture in fixtures)
                    FilterChip(
                      label: Text(fixture.label),
                      selected: settings.fixtureIds.contains(fixture.id),
                      onSelected: (on) => controller.update(
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
            _SliderRow(
              label: 'Sötét hossza',
              value: settings.lengthMs.toDouble(),
              min: DropoutSettings.minLengthMs.toDouble(),
              max: DropoutSettings.maxLengthMs.toDouble(),
              text: '${settings.lengthMs} ms',
              onChanged: (v) => controller.update(settings.copyWith(lengthMs: v.round())),
            ),
            _SliderRow(
              label: 'Átlagos köz',
              value: settings.intervalMs.toDouble(),
              min: DropoutSettings.minIntervalMs.toDouble(),
              max: DropoutSettings.maxIntervalMs.toDouble(),
              text: '${(settings.intervalMs / 1000).toStringAsFixed(1)} s',
              onChanged: (v) => controller.update(settings.copyWith(intervalMs: v.round())),
            ),
            _SliderRow(
              label: 'Szabálytalanság',
              value: settings.jitter,
              min: 0,
              max: 1,
              text: '${(settings.jitter * 100).round()}%',
              onChanged: (v) => controller.update(settings.copyWith(jitter: v)),
            ),
          ],
        ),
      ),
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
