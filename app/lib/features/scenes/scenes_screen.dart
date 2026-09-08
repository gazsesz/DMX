import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/scene_output.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/save_project_action.dart';
import '../../models/scene.dart';
import '../../state/artnet_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/scene_providers.dart';
import 'scene_editor_screen.dart';

class ScenesScreen extends ConsumerStatefulWidget {
  const ScenesScreen({super.key});

  @override
  ConsumerState<ScenesScreen> createState() => _ScenesScreenState();
}

class _ScenesScreenState extends ConsumerState<ScenesScreen> {
  String? _activeSceneId;

  Color _swatchFor(Scene scene) {
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

  Future<void> _openEditor({Scene? scene}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SceneEditorScreen(existing: scene)),
    );
  }

  void _preview(Scene scene) {
    final service = ref.read(artNetServiceProvider);
    if (!service.isConnected) return;
    outputScene(
      service: service,
      scene: scene,
      patchedFixtures: ref.read(patchedFixturesProvider),
      universes: ref.read(universesProvider),
    );
    setState(() => _activeSceneId = scene.id);
  }

  Future<void> _showActions(Scene scene) async {
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
    if (action == 'delete') {
      ref.read(scenesProvider.notifier).remove(scene.id);
      if (_activeSceneId == scene.id) setState(() => _activeSceneId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scenes = ref.watch(scenesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Scenes'), actions: const [SaveProjectAction()]),
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
                final color = _swatchFor(scene);
                final active = scene.id == _activeSceneId;
                return Stack(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: active ? AppColors.accent.withValues(alpha: 0.12) : AppColors.panel,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: active ? AppColors.accent : AppColors.border, width: active ? 2 : 1.5),
                        boxShadow: active
                            ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.35), blurRadius: 10)]
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8.5),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => _preview(scene),
                                onLongPress: () => _showActions(scene),
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
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: active ? AppColors.accent : null,
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        active ? 'Active' : '${scene.fixtureValues.length} fx',
                                        style: TextStyle(
                                          fontSize: 8.5,
                                          color: active ? AppColors.accent : AppColors.textFaint,
                                          fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const Divider(height: 1, thickness: 1, color: AppColors.border),
                            InkWell(
                              onTap: () => _openEditor(scene: scene),
                              child: const SizedBox(
                                width: double.infinity,
                                height: 36,
                                child: Icon(Icons.edit_outlined, size: 18, color: AppColors.textDim),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 3,
                      right: 3,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _showActions(scene),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: AppColors.background.withValues(alpha: 0.7),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.more_vert, size: 14, color: AppColors.textDim),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        tooltip: 'New Scene',
        child: const Icon(Icons.add),
      ),
    );
  }
}
