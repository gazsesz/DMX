import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/scene_output.dart';
import '../../core/theme/app_colors.dart';
import '../../models/scene.dart';
import '../../state/artnet_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/scene_providers.dart';
import 'scene_editor_screen.dart';

class ScenesScreen extends ConsumerWidget {
  const ScenesScreen({super.key});

  Color _swatchFor(Scene scene, WidgetRef ref) {
    final patched = ref.read(patchedFixturesProvider);
    for (final fixture in patched) {
      final values = scene.fixtureValues[fixture.id];
      if (values == null) continue;
      final channels = fixture.profile.channels;
      int? r, g, b;
      for (var i = 0; i < channels.length; i++) {
        switch (channels[i].function.name) {
          case 'red':
            r = values[i];
            break;
          case 'green':
            g = values[i];
            break;
          case 'blue':
            b = values[i];
            break;
        }
      }
      if (r != null || g != null || b != null) {
        return Color.fromARGB(255, r ?? 0, g ?? 0, b ?? 0);
      }
    }
    return AppColors.panel2;
  }

  Future<void> _openEditor(BuildContext context, {Scene? scene}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SceneEditorScreen(existing: scene)),
    );
  }

  void _preview(WidgetRef ref, Scene scene) {
    final service = ref.read(artNetServiceProvider);
    if (!service.isConnected) return;
    outputScene(
      service: service,
      scene: scene,
      patchedFixtures: ref.read(patchedFixturesProvider),
      universes: ref.read(universesProvider),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref, Scene scene) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: AppColors.panel,
        title: Text(scene.name),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'duplicate'),
            child: const Text('Duplicate'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (action == 'duplicate') ref.read(scenesProvider.notifier).duplicate(scene.id);
    if (action == 'delete') ref.read(scenesProvider.notifier).remove(scene.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scenes = ref.watch(scenesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Scenes')),
      body: scenes.isEmpty
          ? const Center(
              child: Text('No scenes yet — tap + to create one', style: TextStyle(color: AppColors.textFaint)),
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              itemCount: scenes.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 110,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.9,
              ),
              itemBuilder: (context, index) {
                final scene = scenes[index];
                final color = _swatchFor(scene, ref);
                return Container(
                  decoration: BoxDecoration(
                    color: AppColors.panel,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border, width: 1.5),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.5),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _preview(ref, scene),
                            onLongPress: () => _showActions(context, ref, scene),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppColors.border),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    scene.name,
                                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${scene.fixtureValues.length} fx',
                                    style: const TextStyle(fontSize: 8.5, color: AppColors.textFaint),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Divider(height: 1, thickness: 1, color: AppColors.border),
                        InkWell(
                          onTap: () => _openEditor(context, scene: scene),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 5),
                            child: Icon(Icons.edit_outlined, size: 13, color: AppColors.textFaint),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(context),
        tooltip: 'New Scene',
        child: const Icon(Icons.add),
      ),
    );
  }
}
