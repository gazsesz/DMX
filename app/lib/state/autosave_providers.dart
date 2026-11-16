import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/project_snapshot.dart';
import '../core/storage/project_storage.dart';
import 'artnet_providers.dart';
import 'bank_providers.dart';
import 'chase_providers.dart';
import 'dashboard_providers.dart';
import 'dimmer_dropout_providers.dart';
import 'fixture_group_providers.dart';
import 'fixture_providers.dart';
import 'layer_providers.dart';
import 'live_providers.dart';
import 'midi_control_providers.dart';
import 'project_providers.dart';
import 'scene_providers.dart';
import 'smart_program_providers.dart';
import 'song_show_providers.dart';
import 'stage_providers.dart';

/// Where the open project stands against its file on disk.
enum ProjectSaveState {
  /// Nothing changed since the last save or load.
  saved,

  /// Edited; an autosave is due shortly.
  dirty,

  /// Being written right now.
  saving,
}

/// How long the show has to sit still before it is written — long enough
/// that dragging a fader doesn't write a file per frame.
final autoSaveDelayProvider = Provider<Duration>((ref) => const Duration(seconds: 3));

final projectStorageProvider = Provider<ProjectStorage>((ref) => ProjectStorage());

/// Every provider [projectSnapshotOf] reads: a change in any of them is a
/// change to the project file.
final List<ProviderListenable<Object?>> _projectProviders = [
  currentProjectNameProvider,
  artNetSettingsProvider,
  universesProvider,
  fixtureLibraryProvider,
  patchedFixturesProvider,
  fixtureGroupsProvider,
  scenesProvider,
  banksProvider,
  chasesProvider,
  dashboardTriggersProvider,
  smartProgramsProvider,
  songShowsProvider,
  layersProvider,
  stagePlanProvider,
  positionPresetsProvider,
  selectedBankIdProvider,
  dimmerDropoutProvider,
  midiMappingsProvider,
  liveGridProvider,
];

final projectAutoSaveProvider = StateNotifierProvider<ProjectAutoSaver, ProjectSaveState>((ref) {
  final saver = ProjectAutoSaver(ref);
  for (final provider in _projectProviders) {
    ref.listen(provider, (_, _) => saver.markChanged());
  }
  return saver;
});

/// Keeps the open project written to its file without anyone pressing Save:
/// a few seconds after the last edit, and straight away when the app leaves
/// the foreground (Android may kill it from there without another word).
///
/// It stays passive — tracking changes but never writing — until [enable]
/// is called once the startup load is done, so a half-loaded show can't
/// overwrite the file it is being loaded from.
class ProjectAutoSaver extends StateNotifier<ProjectSaveState> {
  ProjectAutoSaver(this._ref) : super(ProjectSaveState.saved);

  final Ref _ref;
  bool _enabled = false;
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  Future<bool>? _running;

  /// Bumped on every change, so a save that raced an edit knows it's stale.
  int _revision = 0;

  /// The text last written (or loaded), to skip writes that change nothing.
  String? _lastJson;

  bool get enabled => _enabled;

  void enable() {
    if (_enabled) return;
    _enabled = true;
    _lifecycle = AppLifecycleListener(
      onStateChange: (s) {
        if (s != AppLifecycleState.resumed) unawaited(saveNow());
      },
    );
    if (state == ProjectSaveState.dirty) _schedule();
  }

  void markChanged() {
    if (!mounted) return;
    _revision++;
    if (state != ProjectSaveState.saving) state = ProjectSaveState.dirty;
    _schedule();
  }

  /// The open show matches its file — just loaded, or just written elsewhere.
  void markSaved() {
    if (!mounted) return;
    _timer?.cancel();
    _revision++;
    _lastJson = _encode();
    state = ProjectSaveState.saved;
  }

  void _schedule() {
    if (!_enabled) return;
    _timer?.cancel();
    _timer = Timer(_ref.read(autoSaveDelayProvider), () => unawaited(saveNow()));
  }

  String _encode() => ProjectStorage.encode(projectSnapshotOf(_ref.read));

  /// Writes the show now if it has unsaved changes (or always, with
  /// [force] — the Save button). Returns whether the file is up to date.
  Future<bool> saveNow({bool force = false}) async {
    if (!mounted) return false;
    if (!force && state == ProjectSaveState.saved) return true;
    // One write at a time; a second request just waits for it and re-checks.
    while (_running != null) {
      await _running;
      if (!mounted) return false;
      if (!force && state == ProjectSaveState.saved) return true;
    }
    final run = _write(force);
    _running = run;
    try {
      return await run;
    } finally {
      _running = null;
    }
  }

  Future<bool> _write(bool force) async {
    _timer?.cancel();
    final name = _ref.read(currentProjectNameProvider).trim();
    if (name.isEmpty) return false;
    final revision = _revision;
    final json = _encode();
    if (!force && json == _lastJson) {
      state = ProjectSaveState.saved;
      return true;
    }
    state = ProjectSaveState.saving;
    try {
      await _ref.read(projectStorageProvider).saveEncoded(name, json);
      if (!mounted) return true;
      _lastJson = json;
      if (_revision == revision) {
        state = ProjectSaveState.saved;
      } else {
        // Edited while writing: that edit still needs its own save.
        state = ProjectSaveState.dirty;
        _schedule();
      }
      return true;
    } catch (_) {
      // Disk full or similar: stay dirty and try again on the next change.
      if (mounted) state = ProjectSaveState.dirty;
      return false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }
}
