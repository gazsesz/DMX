import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/scene_output.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/save_project_action.dart';
import '../../models/bank.dart';
import '../../models/scene.dart';
import '../../state/artnet_providers.dart';
import '../../state/bank_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/scene_providers.dart';
import 'scene_editor_screen.dart';

enum _SortMode { manual, name }

enum _GroupMode { none, bank }

class ScenesScreen extends ConsumerStatefulWidget {
  const ScenesScreen({super.key});

  @override
  ConsumerState<ScenesScreen> createState() => _ScenesScreenState();
}

class _ScenesScreenState extends ConsumerState<ScenesScreen> {
  String? _activeSceneId;
  final Set<String> _selectedIds = {};
  _SortMode _sortMode = _SortMode.manual;
  _GroupMode _groupMode = _GroupMode.none;

  bool get _selecting => _selectedIds.isNotEmpty;

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

  void _handleTap(Scene scene) {
    if (_selecting) {
      _toggleSelected(scene.id);
    } else {
      _preview(scene);
    }
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _clearSelection() => setState(_selectedIds.clear);

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text('Delete $count scene${count == 1 ? '' : 's'}?'),
        content: const Text('This also removes them from any bank slots they\'re assigned to.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final notifier = ref.read(scenesProvider.notifier);
    for (final id in _selectedIds) {
      notifier.remove(id);
    }
    if (_selectedIds.contains(_activeSceneId)) _activeSceneId = null;
    setState(_selectedIds.clear);
  }

  void _duplicateSelected() {
    final notifier = ref.read(scenesProvider.notifier);
    for (final id in _selectedIds) {
      notifier.duplicate(id);
    }
    setState(_selectedIds.clear);
  }

  Future<void> _showActions(Scene scene) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: AppColors.panel,
        title: Text(scene.name),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'select'),
            child: const Text('Select (multi)'),
          ),
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
    if (action == 'select') _toggleSelected(scene.id);
    if (action == 'duplicate') ref.read(scenesProvider.notifier).duplicate(scene.id);
    if (action == 'delete') {
      ref.read(scenesProvider.notifier).remove(scene.id);
      if (_activeSceneId == scene.id) setState(() => _activeSceneId = null);
    }
  }

  List<Scene> _sorted(List<Scene> scenes) {
    if (_sortMode == _SortMode.manual) return scenes;
    final copy = [...scenes];
    copy.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return copy;
  }

  /// Bank name (or "Ungrouped") each scene should be filed under — a scene
  /// in more than one bank is filed under the first bank that contains it.
  List<MapEntry<String, List<Scene>>> _groupedByBank(List<Scene> scenes, List<Bank> banks) {
    final groups = <String, List<Scene>>{};
    for (final bank in banks) {
      groups[bank.name] = [];
    }
    const ungrouped = 'Ungrouped';
    groups[ungrouped] = [];
    for (final scene in scenes) {
      final owner = banks.where((b) => b.sceneSlots.contains(scene.id));
      final key = owner.isEmpty ? ungrouped : owner.first.name;
      groups[key]!.add(scene);
    }
    final entries = groups.entries.where((e) => e.value.isNotEmpty).toList();
    entries.sort((a, b) {
      if (a.key == ungrouped) return 1;
      if (b.key == ungrouped) return -1;
      return a.key.compareTo(b.key);
    });
    return entries;
  }

  Widget _sceneGrid(List<Scene> scenes) {
    return GridView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: scenes.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 110,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.9,
      ),
      itemBuilder: (context, index) => _sceneTile(scenes[index]),
    );
  }

  Widget _sceneTile(Scene scene) {
    final color = _swatchFor(scene);
    final active = scene.id == _activeSceneId;
    final selected = _selectedIds.contains(scene.id);
    return Stack(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent2.withValues(alpha: 0.18)
                : active
                    ? AppColors.accent.withValues(alpha: 0.12)
                    : AppColors.panel,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.accent2 : (active ? AppColors.accent : AppColors.border),
              width: selected || active ? 2 : 1.5,
            ),
            boxShadow: active && !selected
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
                    onTap: () => _handleTap(scene),
                    onLongPress: () => _toggleSelected(scene.id),
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
                if (!_selecting) ...[
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
              ],
            ),
          ),
        ),
        Positioned(
          top: 3,
          right: 3,
          child: selected
              ? const Icon(Icons.check_circle, size: 18, color: AppColors.accent2)
              : InkWell(
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
  }

  @override
  Widget build(BuildContext context) {
    final allScenes = _sorted(ref.watch(scenesProvider));
    final banks = ref.watch(banksProvider);

    return Scaffold(
      appBar: _selecting
          ? AppBar(
              leading: IconButton(icon: const Icon(Icons.close), onPressed: _clearSelection),
              title: Text('${_selectedIds.length} selected'),
              actions: [
                IconButton(icon: const Icon(Icons.copy_outlined), tooltip: 'Duplicate', onPressed: _duplicateSelected),
                IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete', onPressed: _deleteSelected),
              ],
            )
          : AppBar(
              title: const Text('Scenes'),
              actions: [
                PopupMenuButton<_SortMode>(
                  tooltip: 'Sort',
                  icon: const Icon(Icons.sort),
                  initialValue: _sortMode,
                  onSelected: (v) => setState(() => _sortMode = v),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: _SortMode.manual, child: Text('Manual order')),
                    PopupMenuItem(value: _SortMode.name, child: Text('Name (A-Z)')),
                  ],
                ),
                PopupMenuButton<_GroupMode>(
                  tooltip: 'Group',
                  icon: const Icon(Icons.workspaces_outlined),
                  initialValue: _groupMode,
                  onSelected: (v) => setState(() => _groupMode = v),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: _GroupMode.none, child: Text('No grouping')),
                    PopupMenuItem(value: _GroupMode.bank, child: Text('Group by Bank')),
                  ],
                ),
                const SaveProjectAction(),
              ],
            ),
      body: allScenes.isEmpty
          ? const Center(
              child: Text('No scenes yet — tap + to create one', style: TextStyle(color: AppColors.textFaint)),
            )
          : _groupMode == _GroupMode.none
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  child: _sceneGrid(allScenes),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  children: [
                    for (final group in _groupedByBank(allScenes, banks)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                        child: Text(
                          '${group.key.toUpperCase()} (${group.value.length})',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: AppColors.textFaint,
                          ),
                        ),
                      ),
                      _sceneGrid(group.value),
                    ],
                  ],
                ),
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton(
              onPressed: () => _openEditor(),
              tooltip: 'New Scene',
              child: const Icon(Icons.add),
            ),
    );
  }
}
