import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../state/dimmer_dropout_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/layer_providers.dart';
import 'dropout_controls.dart';

/// The dimmer dropout's controls on the Layers screen. It sits here because
/// its target is a layer — it cuts what that layer is lighting, not the rig.
/// A Smart Program with its own dropout settings takes over while it runs.
class DimmerDropoutCard extends ConsumerWidget {
  const DimmerDropoutCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(dimmerDropoutProvider);
    final controller = ref.read(dimmerDropoutProvider.notifier);

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
              onChanged: (on) => controller.update(settings.copyWith(enabled: on)),
            ),
            DropoutControls(
              settings: settings,
              onChanged: controller.update,
              layers: ref.watch(layersProvider),
              fixtures: ref.watch(patchedFixturesProvider),
            ),
          ],
        ),
      ),
    );
  }
}
