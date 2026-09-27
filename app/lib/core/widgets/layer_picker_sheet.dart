import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/bank.dart';
import '../../models/layer.dart';
import '../../state/layer_providers.dart';
import '../../state/playback_providers.dart';
import '../theme/app_colors.dart';

/// Asks which layer to run [bank] on — every layer runs independently, so
/// this doesn't stop whatever else is already playing elsewhere.
Future<void> showLayerPickerSheet(BuildContext context, {required Bank bank}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.panel,
    isScrollControlled: true,
    builder: (_) => _LayerPickerSheet(bank: bank),
  );
}

class _LayerPickerSheet extends ConsumerStatefulWidget {
  final Bank bank;

  const _LayerPickerSheet({required this.bank});

  @override
  ConsumerState<_LayerPickerSheet> createState() => _LayerPickerSheetState();
}

class _LayerPickerSheetState extends ConsumerState<_LayerPickerSheet> {
  String? _selectedLayerId;

  @override
  Widget build(BuildContext context) {
    final layers = ref.watch(layersProvider);
    final selectedIndex = _selectedLayerId == null
        ? null
        : layers.indexWhere((l) => l.id == _selectedLayerId);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Futtatás melyik rétegen?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('Bank: ${widget.bank.name}', style: const TextStyle(fontSize: 12.5, color: AppColors.textFaint)),
            const SizedBox(height: 8),
            for (var i = 0; i < layers.length; i++) _layerRow(layers[i], i),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Mégse'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _selectedLayerId == null ? null : _start,
                    child: Text(
                      selectedIndex == null ? 'Indítás' : 'Indítás Layer ${selectedIndex + 1}-en',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _layerRow(Layer layer, int index) {
    final current = ref.watch(nowPlayingForLayerProvider(layer.id));
    final selected = _selectedLayerId == layer.id;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? AppColors.accent : Colors.transparent,
          border: Border.all(color: selected ? AppColors.accent : AppColors.border, width: 1.5),
        ),
      ),
      title: Text('Layer ${index + 1} - ${layer.name}', style: const TextStyle(fontSize: 13.5)),
      subtitle: Text(
        current == null ? 'jelenleg üres' : 'most: ${current.name} fut · felülírja',
        style: TextStyle(fontSize: 11, color: current == null ? AppColors.textFaint : AppColors.accent2),
      ),
      onTap: () => setState(() => _selectedLayerId = layer.id),
    );
  }

  void _start() {
    final layerId = _selectedLayerId;
    if (layerId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final error = runBankOnLayer(ref, bank: widget.bank, layerId: layerId);
    Navigator.pop(context);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }
}
