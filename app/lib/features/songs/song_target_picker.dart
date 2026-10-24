import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/scene.dart';
import '../../models/smart_program.dart';
import '../../models/song_show.dart';
import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';
import '../../state/scene_providers.dart';
import '../scenes/scene_editor_screen.dart';

/// What a cue is to start: a bank or chase ([target]), or one scene.
class SongPick {
  final ProgramTarget? target;
  final String? sceneId;

  const SongPick.target(ProgramTarget this.target) : sceneId = null;
  const SongPick.scene(String this.sceneId) : target = null;
}

/// Which kinds of thing the picker lists.
enum SongPickFilter {
  all('All'),
  banks('Banks'),
  scenes('Scenes'),
  chases('Chases');

  const SongPickFilter(this.label);
  final String label;
}

/// The filter last used, so the next pick opens on it — someone filling a lane
/// with scenes picks scenes again and again.
SongPickFilter _lastFilter = SongPickFilter.all;

/// Puts the remembered filter back to All (for tests).
@visibleForTesting
void resetSongPickFilter() => _lastFilter = SongPickFilter.all;

/// Asks what a cue should start: any bank, scene or chase, narrowed by a
/// filter and a search, with a way to make a new scene on the spot and to copy
/// an existing one. Returns null when dismissed.
Future<SongPick?> showSongTargetPicker(BuildContext context, {String title = 'Start what?'}) {
  return showDialog<SongPick>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      contentPadding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
      content: SizedBox(
        width: 380,
        height: 460,
        child: _PickerBody(dialogContext: dialogContext),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel'))],
    ),
  );
}

class _PickerBody extends ConsumerStatefulWidget {
  const _PickerBody({required this.dialogContext});
  final BuildContext dialogContext;

  @override
  ConsumerState<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends ConsumerState<_PickerBody> {
  SongPickFilter _filter = _lastFilter;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(String name) {
    final q = _search.text.trim().toLowerCase();
    return q.isEmpty || name.toLowerCase().contains(q);
  }

  Future<void> _newScene() async {
    final created = await Navigator.of(widget.dialogContext).push<Scene>(
      MaterialPageRoute(builder: (_) => const SceneEditorScreen()),
    );
    if (created != null && widget.dialogContext.mounted) {
      Navigator.pop(widget.dialogContext, SongPick.scene(created.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final banks = ref.watch(banksProvider);
    final scenes = ref.watch(scenesProvider);
    final chases = ref.watch(chasesProvider);
    final showBanks = _filter == SongPickFilter.all || _filter == SongPickFilter.banks;
    final showScenes = _filter == SongPickFilter.all || _filter == SongPickFilter.scenes;
    final showChases = _filter == SongPickFilter.all || _filter == SongPickFilter.chases;
    final bankRows = showBanks ? [for (final b in banks) if (_matches(b.name)) b] : const <dynamic>[];
    final sceneRows = showScenes ? [for (final s in scenes) if (_matches(s.name)) s] : const <dynamic>[];
    final chaseRows = showChases ? [for (final c in chases) if (_matches(c.name)) c] : const <dynamic>[];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 6,
            children: [
              for (final f in SongPickFilter.values)
                ChoiceChip(
                  key: ValueKey('pick-filter-${f.name}'),
                  label: Text(f.label),
                  selected: f == _filter,
                  onSelected: (_) => setState(() => _filter = _lastFilter = f),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: TextField(
            key: const ValueKey('target-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 18),
              hintText: 'Search by name',
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              if (bankRows.isEmpty && sceneRows.isEmpty && chaseRows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Nothing matches', style: TextStyle(color: AppColors.textFaint)),
                ),
              if (bankRows.isNotEmpty) const _Header('BANKS'),
              for (final bank in bankRows)
                ListTile(
                  key: ValueKey('target-bank-${bank.id}'),
                  dense: true,
                  leading: Icon(
                    bank.isMovementFx ? Icons.open_with : Icons.grid_view_outlined,
                    size: 18,
                    color: AppColors.accent2,
                  ),
                  title: Text(bank.name, style: const TextStyle(fontSize: 13)),
                  onTap: () => Navigator.pop(context, SongPick.target(ProgramTarget(id: bank.id, isBank: true))),
                ),
              if (sceneRows.isNotEmpty) const _Header('SCENES'),
              for (final scene in sceneRows)
                ListTile(
                  key: ValueKey('target-scene-${scene.id}'),
                  dense: true,
                  leading: const Icon(Icons.lightbulb_outline, size: 18, color: AppColors.accent),
                  title: Text(scene.name, style: const TextStyle(fontSize: 13)),
                  trailing: IconButton(
                    key: ValueKey('copy-scene-${scene.id}'),
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    tooltip: 'Make a copy to change',
                    onPressed: () => ref.read(scenesProvider.notifier).duplicate(scene.id),
                  ),
                  onTap: () => Navigator.pop(context, SongPick.scene(scene.id)),
                ),
              if (chaseRows.isNotEmpty) const _Header('CHASES'),
              for (final chase in chaseRows)
                ListTile(
                  key: ValueKey('target-chase-${chase.id}'),
                  dense: true,
                  leading: const Icon(Icons.fast_forward_outlined, size: 18, color: AppColors.accent),
                  title: Text(chase.name, style: const TextStyle(fontSize: 13)),
                  onTap: () => Navigator.pop(context, SongPick.target(ProgramTarget(id: chase.id, isBank: false))),
                ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        ListTile(
          key: const ValueKey('new-scene'),
          dense: true,
          leading: const Icon(Icons.add, size: 18, color: AppColors.accent),
          title: const Text('New scene…', style: TextStyle(fontSize: 13, color: AppColors.accent)),
          onTap: _newScene,
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
    child: Text(
      text,
      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textFaint, letterSpacing: 1),
    ),
  );
}

/// What a cue shows on its block: the bank, scene or chase it starts, "Stop",
/// or a marker when what it pointed at was deleted.
String songCueName(WidgetRef ref, SongCue cue) {
  if (cue.action == SongCueAction.stop) return cue.stopBlackout ? 'Dark' : 'Stop';
  final sceneId = cue.sceneId;
  if (sceneId != null) {
    for (final s in ref.read(scenesProvider)) {
      if (s.id == sceneId) return s.name;
    }
    return '(deleted)';
  }
  final target = cue.target;
  if (target == null) return 'Stop';
  if (target.isBank) {
    for (final b in ref.read(banksProvider)) {
      if (b.id == target.id) return b.name;
    }
  } else {
    for (final c in ref.read(chasesProvider)) {
      if (c.id == target.id) return c.name;
    }
  }
  return '(deleted)';
}
