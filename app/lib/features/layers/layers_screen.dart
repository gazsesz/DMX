import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/control_dock.dart';
import '../../core/widgets/node_status_action.dart';
import '../../core/widgets/save_project_action.dart';
import '../../models/layer.dart';
import '../../state/layer_providers.dart';
import '../../state/playback_providers.dart';

/// Lists every playback layer — what's running on each, and lets the user
/// stop one, rename it, or add/remove layers. Priority and merge-mode are
/// shown as informational text only; the actual conflict-avoidance
/// mechanism is the Scene editor's "INCLUDES" toggles (a scene deliberately
/// leaves the channels another layer owns out of its saved values).
class LayersScreen extends ConsumerStatefulWidget {
  const LayersScreen({super.key});

  @override
  ConsumerState<LayersScreen> createState() => _LayersScreenState();
}

class _LayersScreenState extends ConsumerState<LayersScreen> {
  Future<void> _addLayer() async {
    final layer = ref.read(layersProvider.notifier).addLayer();
    await _editLayer(layer, isNew: true);
  }

  Future<void> _editLayer(Layer layer, {bool isNew = false}) async {
    final nameController = TextEditingController(text: layer.name);
    final hintController = TextEditingController(text: layer.mergeHint);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text(isNew ? 'New Layer' : 'Rename Layer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 8),
            TextField(
              controller: hintController,
              decoration: const InputDecoration(labelText: 'Merge hint (informational)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (result != true || !mounted) return;
    final notifier = ref.read(layersProvider.notifier);
    if (nameController.text.trim().isNotEmpty) {
      notifier.rename(layer.id, nameController.text.trim());
    }
    notifier.setMergeHint(layer.id, hintController.text.trim());
  }

  Future<void> _deleteLayer(Layer layer) async {
    final current = ref.read(nowPlayingForLayerProvider(layer.id));
    final ok = await confirmDelete(
      context,
      title: 'Delete "${layer.name}"?',
      message: current == null
          ? 'This layer is currently empty.'
          : 'This will stop "${current.name}", currently running on this layer.',
    );
    if (!ok || !mounted) return;
    stopLayer(ref, layer.id);
    ref.read(layersProvider.notifier).remove(layer.id);
  }

  @override
  Widget build(BuildContext context) {
    final layers = ref.watch(layersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Layers'),
        actions: const [NodeStatusAction(), ControlDockAction(), SaveProjectAction()],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Egyszerre futó programok', style: TextStyle(fontSize: 12.5, color: AppColors.textFaint)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              children: [
                for (var i = 0; i < layers.length; i++) _layerCard(layers[i], i),
                ListTile(
                  leading: const Icon(Icons.add, color: AppColors.accent),
                  title: const Text('Új réteg hozzáadása', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                  onTap: _addLayer,
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'Csatorna-merge: dimmer → HTP · pan/tilt, szín → LTP (prioritás)',
              style: TextStyle(fontSize: 11, color: AppColors.textFaint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _layerCard(Layer layer, int index) {
    final current = ref.watch(nowPlayingForLayerProvider(layer.id));
    final isPlaying = ref.watch(chasePlayerProvider(layer.id)).isPlaying;
    final isLayer1 = layer.id == layer1Id;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.accent2On,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('L${index + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.accent2)),
        ),
        title: Row(
          children: [
            Flexible(child: Text(current?.name ?? layer.name, overflow: TextOverflow.ellipsis)),
            if (isPlaying) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(4)),
                child: const Text('FUT', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.black)),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${current == null ? 'Nincs program fut' : current.kind.name}\n'
          'Priority ${layer.priority}${layer.mergeHint.isEmpty ? '' : ' · ${layer.mergeHint}'}',
          style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'Stop',
              color: isPlaying ? AppColors.danger : AppColors.textFaint,
              onPressed: isPlaying ? () => stopLayer(ref, layer.id) : null,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete layer',
              color: isLayer1 ? AppColors.textFaint : AppColors.danger,
              onPressed: isLayer1 ? null : () => _deleteLayer(layer),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: 'Edit layer',
              onPressed: () => _editLayer(layer),
            ),
          ],
        ),
      ),
    );
  }
}
