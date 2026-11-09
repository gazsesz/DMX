import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/song/audio_probe.dart';
import '../../core/song/cue_resize.dart';
import '../../core/song/song_timeline_math.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/control_dock.dart' show LiveStageDock;
import '../../core/widgets/confirm_dialog.dart';
import '../../models/layer.dart';
import '../../models/smart_program.dart';
import '../../models/song_show.dart';
import '../../state/bank_providers.dart';
import '../../state/control_dock_providers.dart';
import '../../state/fixture_group_providers.dart';
import '../../state/layer_providers.dart';
import '../../state/song_show_providers.dart';
import '../../state/song_view_providers.dart';
import 'pinch_zoom.dart';
import 'song_auto_screen.dart';
import 'song_section_dialog.dart';
import 'song_stop_dialog.dart';
import 'song_target_picker.dart';
import 'song_timeline.dart';
import '../../l10n/l10n.dart';
import '../../l10n/labels.dart';
import '../../l10n/status_messages.dart';

const _uuid = Uuid();

/// Edits one [SongShow]: link the song, set its tempo and beat grid, mark
/// sections, and place cues on the layers' lanes — by tapping a lane, by
/// dragging, or by pressing bank buttons while the song plays (Record).
class SongShowEditorScreen extends ConsumerStatefulWidget {
  const SongShowEditorScreen({super.key, required this.showId});

  final String showId;

  @override
  ConsumerState<SongShowEditorScreen> createState() => _SongShowEditorScreenState();
}

class _SongShowEditorScreenState extends ConsumerState<SongShowEditorScreen> {
  final _scroll = ScrollController();
  final _playhead = ValueNotifier<double?>(null);
  final _pinch = PinchState();
  TimelineScale _scale = const TimelineScale(32);
  SongSnap _snap = SongSnap.beat;
  double _cursorBeat = 0;
  String? _selectedCueId;
  Float32List? _waveform;
  int _waveformBins = waveformBinsPerSecond;
  String? _waveformPath;
  Timer? _ticker;
  bool _recording = false;
  String? _recordLayerId;

  /// A cue copied from the timeline, waiting to be pasted onto a lane.
  SongCue? _clipboard;

  SongShow? get _show {
    for (final s in ref.read(songShowsProvider)) {
      if (s.id == widget.showId) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients) _lastOffset = _scroll.offset;
    });
    // Come back to the zoom and place the timeline was left at.
    final saved = rememberedSongView(widget.showId);
    if (saved != null) {
      _restoreView(saved);
    } else {
      unawaited(_restoreSavedView());
    }
    _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadWaveform());
  }

  void _restoreView(SongView view) {
    _scale = TimelineScale(view.pixelsPerBeat.clamp(TimelineScale.minPixelsPerBeat, TimelineScale.maxPixelsPerBeat));
    _lastOffset = view.scrollOffset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(view.scrollOffset.clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  /// A show opened for the first time this session: its view from the last one.
  Future<void> _restoreSavedView() async {
    final view = await loadSongView(widget.showId);
    if (view == null || !mounted || _zoomTouched) return;
    setState(() => _restoreView(view));
  }

  /// Whether the zoom was changed since the editor opened (then an older saved
  /// view must not override what the user just did).
  bool _zoomTouched = false;
  double _lastOffset = 0;

  void _setScale(TimelineScale scale) {
    _zoomTouched = true;
    setState(() => _scale = scale);
  }

  @override
  void dispose() {
    final view = SongView(pixelsPerBeat: _scale.pixelsPerBeat, scrollOffset: _lastOffset);
    rememberSongView(widget.showId, view);
    _ticker?.cancel();
    _scroll.dispose();
    _playhead.dispose();
    _pinch.dispose();
    super.dispose();
  }

  bool get _isPlaying => ref.read(playingSongShowIdProvider) == widget.showId;

  void _tick() {
    final show = _show;
    if (!mounted || show == null) return;
    if (!_isPlaying) {
      if (_playhead.value != null) _playhead.value = null;
      return;
    }
    final player = ref.read(songShowPlayerProvider);
    final beat = show.beatAtMs(player.position.inMicroseconds / 1000);
    _playhead.value = beat;
    if (_scroll.hasClients) {
      final x = _scale.x(beat);
      final view = _scroll.position.viewportDimension;
      if (x < _scroll.offset || x > _scroll.offset + view - 40) {
        _scroll.jumpTo((x - 40).clamp(0, _scroll.position.maxScrollExtent));
      }
    }
  }

  void _snackText(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(localizeStatus(message, context.l10n))));
  }

  void _save(SongShow show) {
    ref.read(songShowsProvider.notifier).upsert(show);
    updateRunningSongShow(ref.read, show);
  }

  Future<void> _loadWaveform() async {
    final path = _show?.audio?.path;
    if (path == null || path == _waveformPath) return;
    _waveformPath = path;
    try {
      final probe = await probeAudio(path);
      if (!mounted) return;
      setState(() {
        _waveform = probe.waveform;
        _waveformBins = probe.binsPerSecond;
      });
    } catch (_) {
      if (mounted) setState(() => _waveform = null);
    }
  }

  Future<void> _pickAudio() async {
    final show = _show;
    if (show == null) return;
    final picked = await FilePicker.pickFiles(type: FileType.audio);
    final file = picked.firstOrNull;
    final path = file?.path;
    if (file == null || path == null) return;
    try {
      final probe = await probeAudio(path);
      if (!mounted) return;
      final previous = show.audio;
      if (previous != null && !previous.couldBeSameSong(probe.length.inMilliseconds)) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.l10n.songIsThisTheSame),
            content: Text(
              context.l10n.songIsLongButThis(file.name, _clock(probe.length.inMilliseconds), previous.fileName, _clock(previous.durationMs)),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.commonCancel)),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.l10n.songLinkAnyway)),
            ],
          ),
        );
        if (proceed != true || !mounted) return;
      }
      _save(show.copyWith(
        audio: SongAudioRef(fileName: file.name, durationMs: probe.length.inMilliseconds, path: path),
      ));
      setState(() {
        _waveform = probe.waveform;
        _waveformBins = probe.binsPerSecond;
        _waveformPath = path;
      });
    } catch (e) {
      _snackText(context.l10n.songCouldNotRead(file.name, e));
    }
  }

  String _clock(int ms) {
    final s = (ms / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _pickGroups() async {
    final show = _show;
    if (show == null) return;
    final groups = ref.read(fixtureGroupsProvider);
    final chosen = {...show.groupIds};
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(context.l10n.songPlayOnWhichFixtures),
          content: SizedBox(
            width: 340,
            child: groups.isEmpty
                ? Text(context.l10n.songNoFixtureGroupsYet)
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final g in groups)
                        CheckboxListTile(
                          key: ValueKey('scope-${g.id}'),
                          dense: true,
                          title: Text(g.name),
                          subtitle: Text(context.l10n.songFixtures(g.fixtureIds.length)),
                          value: chosen.contains(g.id),
                          onChanged: (v) => setLocal(() => v == true ? chosen.add(g.id) : chosen.remove(g.id)),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, <String>[]), child: Text(context.l10n.wAllFixtures)),
            FilledButton(
              key: const ValueKey('scope-done'),
              onPressed: () => Navigator.pop(context, chosen.toList()),
              child: Text(context.l10n.commonDone),
            ),
          ],
        ),
      ),
    );
    if (result != null) _save(show.copyWith(groupIds: result));
  }

  Future<void> _togglePlay() async {
    final show = _show;
    if (show == null) return;
    if (_isPlaying) {
      stopSongShow(ref.read);
      setState(() => _recording = false);
      return;
    }
    final from = Duration(milliseconds: show.msOfBeat(_cursorBeat).round().clamp(0, 1 << 31));
    final error = await startSongShow(ref.read, show, from: from);
    if (error != null) _snackText(localizeStatus(error, context.l10n));
    if (mounted) setState(() {});
  }

  Future<void> _renameShow() async {
    final show = _show;
    if (show == null) return;
    final controller = TextEditingController(text: show.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.songSongShowName),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(context.l10n.commonSave)),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) _save(show.copyWith(name: name));
  }

  Future<void> _editTempo() async {
    final show = _show;
    if (show == null) return;
    final bpm = await showDialog<double>(context: context, builder: (_) => _TempoDialog(initial: show.bpm));
    if (bpm != null && bpm >= 40 && bpm <= 250) _save(show.copyWith(bpm: bpm));
  }

  void _nudgeOffset(int deltaMs) {
    final show = _show;
    if (show == null) return;
    _save(show.copyWith(beatOffsetMs: show.beatOffsetMs + deltaMs));
  }

  void _addCue(SongShow show, SongCue cue) {
    _save(show.copyWith(cues: [...show.cues, cue]));
    setState(() => _selectedCueId = cue.id);
  }

  Future<void> _tapLane(String layerId, double beat) async {
    final show = _show;
    if (show == null) return;
    setState(() => _cursorBeat = beat);
    final clip = _clipboard;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('add-start-cue'),
              leading: const Icon(Icons.play_arrow),
              title: Text(context.l10n.songStartABankScene),
              onTap: () => Navigator.pop(context, 'start'),
            ),
            if (clip != null)
              ListTile(
                key: const ValueKey('paste-cue'),
                leading: const Icon(Icons.content_paste),
                title: Text(context.l10n.songPaste(songCueName(ref, clip, context.l10n))),
                onTap: () => Navigator.pop(context, 'paste'),
              ),
            ListTile(
              key: const ValueKey('add-stop-cue'),
              leading: const Icon(Icons.stop),
              title: Text(context.l10n.songStopThisLayerHere),
              onTap: () => Navigator.pop(context, 'stop'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'stop') {
      final how = await showStopDialog(context);
      final latest = _show;
      if (how == null || latest == null || !mounted) return;
      _addCue(
        latest,
        SongCue(
          id: _uuid.v4(),
          atBeat: beat,
          layerId: layerId,
          action: SongCueAction.stop,
          stopBlackout: how.blackout,
          stopFadeMs: how.fadeMs,
        ),
      );
      return;
    }
    if (choice == 'paste' && clip != null) {
      _addCue(show, clip.duplicatedAs(_uuid.v4(), atBeat: beat, layerId: layerId));
      return;
    }
    final pick = await showSongTargetPicker(context);
    if (pick == null || !mounted) return;
    final latest = _show;
    if (latest == null) return;
    _addCue(
      latest,
      SongCue(id: _uuid.v4(), atBeat: beat, layerId: layerId, target: pick.target, sceneId: pick.sceneId),
    );
  }

  Future<void> _tapCue(SongCue cue) async {
    setState(() => _selectedCueId = cue.id);
    final isStart = cue.action == SongCueAction.start;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isStart)
              ListTile(
                key: const ValueKey('cue-try'),
                leading: const Icon(Icons.play_circle_outline),
                title: Text(context.l10n.songTryItNow),
                subtitle: Text(context.l10n.songPlaysThisLookOn),
                onTap: () => Navigator.pop(context, 'try'),
              ),
            if (!isStart)
              ListTile(
                key: const ValueKey('cue-stop-mode'),
                leading: const Icon(Icons.nights_stay_outlined),
                title: Text(context.l10n.songHowItEnds),
                subtitle: Text(cue.stopBlackout ? context.l10n.songBlackout(stopFadeLabel(context, cue.stopFadeMs)) : context.l10n.songKeepsTheLastLook),
                onTap: () => Navigator.pop(context, 'stop-mode'),
              ),
            ListTile(
              key: const ValueKey('cue-stop-layer'),
              leading: const Icon(Icons.stop_circle_outlined),
              title: Text(context.l10n.songStopThisLayerNow),
              onTap: () => Navigator.pop(context, 'stop-layer'),
            ),
            ListTile(
              key: const ValueKey('cue-change'),
              leading: const Icon(Icons.swap_horiz),
              title: Text(isStart ? context.l10n.songChangeWhatItStarts : context.l10n.songStartSomethingInstead),
              onTap: () => Navigator.pop(context, 'change'),
            ),
            ListTile(
              key: const ValueKey('cue-copy'),
              leading: const Icon(Icons.copy_outlined),
              title: Text(context.l10n.songCopy),
              subtitle: Text(context.l10n.songThenTapALane),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListTile(
              key: const ValueKey('cue-delete'),
              leading: const Icon(Icons.delete_outline),
              title: Text(context.l10n.songDeleteCue),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    final show = _show;
    if (!mounted || show == null || choice == null) return;
    switch (choice) {
      case 'delete':
        _save(show.copyWith(cues: [for (final c in show.cues) if (c.id != cue.id) c]));
        setState(() => _selectedCueId = null);
      case 'copy':
        setState(() => _clipboard = cue);
        _snackText(context.l10n.songCopiedTapALane(songCueName(ref, cue, context.l10n)));
      case 'try':
        previewSongCue(ref.read, cue);
      case 'stop-mode':
        final how = await showStopDialog(
          context,
          initial: StopChoice(blackout: cue.stopBlackout, fadeMs: cue.stopFadeMs),
        );
        final latest = _show;
        if (how == null || latest == null || !mounted) return;
        _replaceCue(latest, cue.asStop(blackout: how.blackout, fadeMs: how.fadeMs));
      case 'stop-layer':
        stopSongLayer(ref.read, cue.layerId);
      case 'change':
        final pick = await showSongTargetPicker(context);
        final latest = _show;
        if (pick == null || latest == null || !mounted) return;
        _replaceCue(latest, pick.sceneId != null ? cue.startingScene(pick.sceneId!) : cue.startingTarget(pick.target!));
    }
  }

  void _replaceCue(SongShow show, SongCue next) =>
      _save(show.copyWith(cues: [for (final c in show.cues) if (c.id == next.id) next else c]));

  /// A long press on a cue and a drag of its end: moves the Stop that ends it,
  /// adds one, or shifts the hand-over to the look after it.
  void _resizeCue(SongCue cue, double endBeat) {
    final show = _show;
    if (show == null) return;
    final cues = resizeCueEnd(show, cue, endBeat, newId: _uuid.v4);
    if (cues == null) {
      _snackText(context.l10n.songItCannotEndThere);
      return;
    }
    _save(show.copyWith(cues: cues));
  }

  void _moveCue(SongCue cue, double beat) {
    final show = _show;
    if (show == null) return;
    _replaceCue(show, cue.copyWith(atBeat: beat));
  }

  Future<void> _editSection(SongSection section) async {
    final show = _show;
    if (show == null) return;
    final result = await showSectionDialog(context, section: section);
    if (result == null || !mounted) return;
    final others = [for (final s in show.sections) if (s.startBeat != section.startBeat) s];
    _save(show.copyWith(sections: result.delete ? others : _sorted([...others, result.section!])));
  }

  Future<void> _addSection(double beat) async {
    final show = _show;
    if (show == null) return;
    setState(() => _cursorBeat = beat);
    final result = await showSectionDialog(
      context,
      section: SongSection(startBeat: beat, lengthBeats: 16, kind: SongSectionKind.drop),
      isNew: true,
    );
    final latest = _show;
    if (result == null || result.delete || latest == null || !mounted) return;
    _save(latest.copyWith(sections: _sorted([...latest.sections, result.section!])));
  }

  List<SongSection> _sorted(List<SongSection> s) => [...s]..sort((a, b) => a.startBeat.compareTo(b.startBeat));

  void _tapRuler(double beat) {
    setState(() => _cursorBeat = beat);
    final show = _show;
    if (show != null && _isPlaying) {
      ref.read(songShowPlayerProvider).seek(Duration(milliseconds: show.msOfBeat(beat).round().clamp(0, 1 << 31)));
    }
  }

  void _recordPress(ProgramTarget? target) {
    final show = _show;
    final layerId = _recordLayerId ?? ref.read(layersProvider).first.id;
    if (show == null || !_isPlaying) return;
    final beat = recordBeat(show, ref.read(songShowPlayerProvider).position, _snap);
    _addCue(
      show,
      SongCue(
        id: _uuid.v4(),
        atBeat: beat,
        layerId: layerId,
        action: target == null ? SongCueAction.stop : SongCueAction.start,
        target: target,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shows = ref.watch(songShowsProvider);
    final layers = ref.watch(layersProvider);
    final playing = ref.watch(playingSongShowIdProvider) == widget.showId;
    final stageVisible = ref.watch(controlDockProvider.select((d) => d.stageVisible));
    final matches = shows.where((s) => s.id == widget.showId);
    if (matches.isEmpty) {
      return Scaffold(body: Center(child: Text(context.l10n.songThisSongShowNo)));
    }
    final show = matches.first;
    final audio = show.audio;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(onTap: _renameShow, child: Text(show.name)),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: context.l10n.scRename, onPressed: _renameShow),
          IconButton(
            key: const ValueKey('song-live-stage'),
            tooltip: stageVisible ? context.l10n.wHideLiveStage : context.l10n.wShowLiveStage,
            icon: Icon(
              stageVisible ? Icons.lightbulb : Icons.lightbulb_outline,
              color: stageVisible ? AppColors.accent2 : null,
            ),
            onPressed: () => ref.read(controlDockProvider.notifier).toggleStageVisible(),
          ),
          IconButton(
            key: const ValueKey('song-play'),
            icon: Icon(playing ? Icons.stop_circle_outlined : Icons.play_circle_outline, size: 30),
            tooltip: playing ? context.l10n.commonStop : context.l10n.songPlayFromTheCursor,
            onPressed: _togglePlay,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('song-pick-audio'),
                  onPressed: _pickAudio,
                  icon: const Icon(Icons.audio_file_outlined, size: 18),
                  label: Text(audio == null ? context.l10n.songPickAudioFile : audio.fileName, overflow: TextOverflow.ellipsis),
                ),
                OutlinedButton(
                  key: const ValueKey('song-tempo'),
                  onPressed: _editTempo,
                  child: Text('${show.bpm.toStringAsFixed(show.bpm == show.bpm.roundToDouble() ? 0 : 1)} BPM'),
                ),
                _Nudge(
                  label: context.l10n.songGridMs(show.beatOffsetMs),
                  onMinus: () => _nudgeOffset(-10),
                  onPlus: () => _nudgeOffset(10),
                ),
                DropdownButton<SongSnap>(
                  value: _snap,
                  underline: const SizedBox.shrink(),
                  items: [for (final s in SongSnap.values) DropdownMenuItem(value: s, child: Text(context.l10n.songSnap(s.tr(context.l10n))))],
                  onChanged: (v) => setState(() => _snap = v ?? _snap),
                ),
                IconButton(
                  tooltip: context.l10n.songZoomOut,
                  icon: const Icon(Icons.zoom_out),
                  onPressed: () => _setScale(_scale.zoomed(0.7)),
                ),
                IconButton(
                  tooltip: context.l10n.songZoomIn,
                  icon: const Icon(Icons.zoom_in),
                  onPressed: () => _setScale(_scale.zoomed(1 / 0.7)),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('song-scope'),
                  onPressed: _pickGroups,
                  icon: const Icon(Icons.lightbulb_outline, size: 18),
                  label: Text(show.groupIds.isEmpty ? context.l10n.wAllFixtures : '${show.groupIds.length} group${show.groupIds.length == 1 ? '' : 's'}'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('song-auto'),
                  onPressed: audio?.path == null
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => SongAutoScreen(showId: show.id)),
                        ),
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Auto'),
                ),
                FilterChip(
                  key: const ValueKey('song-record'),
                  label: Text(context.l10n.songRecord),
                  avatar: const Icon(Icons.fiber_manual_record, size: 14, color: AppColors.danger),
                  selected: _recording,
                  onSelected: (v) => setState(() => _recording = v && playing),
                ),
              ],
            ),
          ),
          if (audio == null || audio.path == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                audio == null
                    ? context.l10n.songNoAudioLinkedThe
                    : context.l10n.songTheSongFileIsn(audio.fileName),
                key: const ValueKey('audio-banner'),
                style: TextStyle(fontSize: 11, color: audio == null ? AppColors.textFaint : AppColors.accent),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 2, 12, 4),
            child: Text(
              context.l10n.songTapALaneTo,
              key: ValueKey('timeline-hint'),
              style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: SongTimeline(
                show: show,
                layers: layers,
                scale: _scale,
                scrollController: _scroll,
                snap: _snap,
                waveform: _waveform,
                waveformBinsPerSecond: _waveformBins,
                playheadBeat: _playhead,
                cursorBeat: _cursorBeat,
                selectedCueId: _selectedCueId,
                cueName: (c) => songCueName(ref, c, context.l10n),
                onTapRuler: _tapRuler,
                onTapLane: _tapLane,
                onTapCue: _tapCue,
                onMoveCue: _moveCue,
                onResizeCue: _resizeCue,
                pinch: _pinch,
                onScaleChanged: _setScale,
                onTapSection: _editSection,
                onTapSectionRow: _addSection,
              ),
            ),
          ),
          _TransportBar(
            show: show,
            playing: playing,
            playhead: _playhead,
            cursorBeat: _cursorBeat,
            onToggle: _togglePlay,
          ),
          if (_recording && playing) _RecordBar(layers: layers, layerId: _recordLayerId, onLayer: _pickRecordLayer, onPress: _recordPress),
          // The same live stage strip the main tabs have, so the lamps and
          // moving heads can be watched while the cues are being placed.
          if (stageVisible) const LiveStageDock(),
        ],
      ),
    );
  }

  void _pickRecordLayer(String id) => setState(() => _recordLayerId = id);
}

class _Nudge extends StatelessWidget {
  const _Nudge({required this.label, required this.onMinus, required this.onPlus});
  final String label;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: onMinus, tooltip: context.l10n.songGrid10MsEarlier),
      Text(label, style: const TextStyle(fontSize: 12)),
      IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: onPlus, tooltip: context.l10n.songGrid10MsLater),
    ],
  );
}

/// Record mode: while the song plays, a press on a bank lands a cue on the
/// grid at the song position, on the chosen layer.
class _RecordBar extends ConsumerWidget {
  const _RecordBar({required this.layers, required this.layerId, required this.onLayer, required this.onPress});
  final List<Layer> layers;
  final String? layerId;
  final void Function(String id) onLayer;
  final void Function(ProgramTarget? target) onPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final banks = ref.watch(banksProvider);
    final selected = layerId ?? layers.first.id;
    return Container(
      color: AppColors.panel2,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fiber_manual_record, size: 14, color: AppColors.danger),
              const SizedBox(width: 6),
              Text(context.l10n.songRecordingOn, style: TextStyle(fontSize: 12)),
              const SizedBox(width: 8),
              for (final l in layers)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(l.name),
                    selected: l.id == selected,
                    onSelected: (_) => onLayer(l.id),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final b in banks)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      key: ValueKey('rec-bank-${b.id}'),
                      label: Text(b.name),
                      onPressed: () => onPress(ProgramTarget(id: b.id, isBank: true)),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    key: const ValueKey('rec-stop'),
                    avatar: const Icon(Icons.stop, size: 16),
                    label: Text(context.l10n.commonStop),
                    onPressed: () => onPress(null),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TempoDialog extends StatefulWidget {
  const _TempoDialog({required this.initial});
  final double initial;

  @override
  State<_TempoDialog> createState() => _TempoDialogState();
}

class _TempoDialogState extends State<_TempoDialog> {
  late final _controller = TextEditingController(text: widget.initial.toStringAsFixed(1));
  final _taps = <int>[];

  void _tap() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_taps.isNotEmpty && now - _taps.last > 2000) _taps.clear();
    _taps.add(now);
    final bpm = tapTempo(_taps);
    if (bpm != null) setState(() => _controller.text = bpm.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.songTempo),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const ValueKey('tempo-field'),
          controller: _controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: 'BPM'),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _tap, child: Text(context.l10n.songTapTempo)),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.commonCancel)),
      FilledButton(
        onPressed: () => Navigator.pop(context, double.tryParse(_controller.text.replaceAll(',', '.'))),
        child: Text(context.l10n.songSet),
      ),
    ],
  );
}

/// Confirms and removes [show]; used by the list.
Future<bool> confirmDeleteSongShow(BuildContext context, SongShow show) => confirmDelete(
  context,
  title: context.l10n.layersDeleteTitle(show.name),
  message: context.l10n.songItsTimelineGoesWith,
);

/// Play and Stop where the thumb is, with where in the song it is — editing
/// and testing go hand in hand. A show without a song file plays silently, on
/// its tempo, so the lights can still be tried.
class _TransportBar extends StatelessWidget {
  const _TransportBar({
    required this.show,
    required this.playing,
    required this.playhead,
    required this.cursorBeat,
    required this.onToggle,
  });

  final SongShow show;
  final bool playing;
  final ValueListenable<double?> playhead;
  final double cursorBeat;
  final VoidCallback onToggle;

  static String barBeat(BuildContext context, double beat) {
    final b = beat < 0 ? 0.0 : beat;
    return context.l10n.songBarBeat(b ~/ 4 + 1, (b % 4).floor() + 1);
  }

  @override
  Widget build(BuildContext context) {
    final silent = show.audio?.path == null;
    return Container(
      color: AppColors.panel2,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          FilledButton.icon(
            key: const ValueKey('transport-play'),
            onPressed: onToggle,
            style: playing ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
            icon: Icon(playing ? Icons.stop : Icons.play_arrow),
            label: Text(playing ? context.l10n.commonStop : context.l10n.songPlay),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ValueListenableBuilder<double?>(
              valueListenable: playhead,
              builder: (context, beat, _) => Text(
                playing && beat != null
                    ? context.l10n.songPlaying(barBeat(context, beat))
                    : context.l10n.songStartsFromTapThe(barBeat(context, cursorBeat)),
                key: const ValueKey('transport-position'),
                style: const TextStyle(fontSize: 12, color: AppColors.textDim),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (silent)
            Tooltip(
              message: context.l10n.songNoSongFileLinked,
              child: Icon(Icons.volume_off, size: 18, color: AppColors.textFaint),
            ),
        ],
      ),
    );
  }
}
