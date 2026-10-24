import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/song/audio_probe.dart';
import '../../core/song/song_timeline_math.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../models/layer.dart';
import '../../models/smart_program.dart';
import '../../models/song_show.dart';
import '../../state/bank_providers.dart';
import '../../state/layer_providers.dart';
import '../../state/song_show_providers.dart';
import 'song_auto_screen.dart';
import 'song_section_dialog.dart';
import 'song_target_picker.dart';
import 'song_timeline.dart';

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

  SongShow? get _show {
    for (final s in ref.read(songShowsProvider)) {
      if (s.id == widget.showId) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadWaveform());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scroll.dispose();
    _playhead.dispose();
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
      _save(show.copyWith(
        audio: SongAudioRef(fileName: file.name, durationMs: probe.length.inMilliseconds, path: path),
      ));
      setState(() {
        _waveform = probe.waveform;
        _waveformBins = probe.binsPerSecond;
        _waveformPath = path;
      });
    } catch (e) {
      _snackText('Could not read ${file.name}: $e');
    }
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
    if (error != null) _snackText(error);
    if (mounted) setState(() {});
  }

  Future<void> _renameShow() async {
    final show = _show;
    if (show == null) return;
    final controller = TextEditingController(text: show.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Song show name'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
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
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('add-start-cue'),
              leading: const Icon(Icons.play_arrow),
              title: const Text('Start a bank or chase here'),
              onTap: () => Navigator.pop(context, 'start'),
            ),
            ListTile(
              key: const ValueKey('add-stop-cue'),
              leading: const Icon(Icons.stop),
              title: const Text('Stop this layer here'),
              onTap: () => Navigator.pop(context, 'stop'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'stop') {
      _addCue(show, SongCue(id: _uuid.v4(), atBeat: beat, layerId: layerId, action: SongCueAction.stop));
      return;
    }
    final target = await showSongTargetPicker(context);
    if (target == null || !mounted) return;
    final latest = _show;
    if (latest == null) return;
    _addCue(latest, SongCue(id: _uuid.v4(), atBeat: beat, layerId: layerId, target: target));
  }

  Future<void> _tapCue(SongCue cue) async {
    setState(() => _selectedCueId = cue.id);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('cue-change'),
              leading: const Icon(Icons.swap_horiz),
              title: Text(cue.action == SongCueAction.stop ? 'Start something instead' : 'Change what it starts'),
              onTap: () => Navigator.pop(context, 'change'),
            ),
            if (cue.action == SongCueAction.start)
              ListTile(
                key: const ValueKey('cue-make-stop'),
                leading: const Icon(Icons.stop),
                title: const Text('Make it a stop'),
                onTap: () => Navigator.pop(context, 'stop'),
              ),
            ListTile(
              key: const ValueKey('cue-delete'),
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete cue'),
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
      case 'stop':
        _replaceCue(show, SongCue(id: cue.id, atBeat: cue.atBeat, layerId: cue.layerId, action: SongCueAction.stop));
      case 'change':
        final target = await showSongTargetPicker(context);
        final latest = _show;
        if (target == null || latest == null || !mounted) return;
        _replaceCue(latest, SongCue(id: cue.id, atBeat: cue.atBeat, layerId: cue.layerId, target: target));
    }
  }

  void _replaceCue(SongShow show, SongCue next) =>
      _save(show.copyWith(cues: [for (final c in show.cues) if (c.id == next.id) next else c]));

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
    final matches = shows.where((s) => s.id == widget.showId);
    if (matches.isEmpty) {
      return const Scaffold(body: Center(child: Text('This song show no longer exists')));
    }
    final show = matches.first;
    final audio = show.audio;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(onTap: _renameShow, child: Text(show.name)),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Rename', onPressed: _renameShow),
          IconButton(
            key: const ValueKey('song-play'),
            icon: Icon(playing ? Icons.stop_circle_outlined : Icons.play_circle_outline, size: 30),
            tooltip: playing ? 'Stop' : 'Play from the cursor',
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
                  label: Text(audio == null ? 'Pick audio file' : audio.fileName, overflow: TextOverflow.ellipsis),
                ),
                OutlinedButton(
                  key: const ValueKey('song-tempo'),
                  onPressed: _editTempo,
                  child: Text('${show.bpm.toStringAsFixed(show.bpm == show.bpm.roundToDouble() ? 0 : 1)} BPM'),
                ),
                _Nudge(
                  label: 'Grid ${show.beatOffsetMs} ms',
                  onMinus: () => _nudgeOffset(-10),
                  onPlus: () => _nudgeOffset(10),
                ),
                DropdownButton<SongSnap>(
                  value: _snap,
                  underline: const SizedBox.shrink(),
                  items: [for (final s in SongSnap.values) DropdownMenuItem(value: s, child: Text('Snap: ${s.label}'))],
                  onChanged: (v) => setState(() => _snap = v ?? _snap),
                ),
                IconButton(
                  tooltip: 'Zoom out',
                  icon: const Icon(Icons.zoom_out),
                  onPressed: () => setState(() => _scale = _scale.zoomed(0.7)),
                ),
                IconButton(
                  tooltip: 'Zoom in',
                  icon: const Icon(Icons.zoom_in),
                  onPressed: () => setState(() => _scale = _scale.zoomed(1 / 0.7)),
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
                  label: const Text('Record'),
                  avatar: const Icon(Icons.fiber_manual_record, size: 14, color: AppColors.danger),
                  selected: _recording,
                  onSelected: (v) => setState(() => _recording = v && playing),
                ),
              ],
            ),
          ),
          if (audio == null)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'No audio linked — the timeline still works from the tempo, but playing needs a song file.',
                style: TextStyle(fontSize: 11, color: AppColors.textFaint),
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
                targetName: (t) => songTargetName(ref, t),
                onTapRuler: _tapRuler,
                onTapLane: _tapLane,
                onTapCue: _tapCue,
                onMoveCue: _moveCue,
                onTapSection: _editSection,
                onTapSectionRow: _addSection,
              ),
            ),
          ),
          if (_recording && playing) _RecordBar(layers: layers, layerId: _recordLayerId, onLayer: _pickRecordLayer, onPress: _recordPress),
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
      IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: onMinus, tooltip: 'Grid 10 ms earlier'),
      Text(label, style: const TextStyle(fontSize: 12)),
      IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: onPlus, tooltip: 'Grid 10 ms later'),
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
              const Text('Recording on', style: TextStyle(fontSize: 12)),
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
                    label: const Text('Stop'),
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
    title: const Text('Tempo'),
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
        FilledButton(onPressed: _tap, child: const Text('Tap tempo')),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: () => Navigator.pop(context, double.tryParse(_controller.text.replaceAll(',', '.'))),
        child: const Text('Set'),
      ),
    ],
  );
}

/// Confirms and removes [show]; used by the list.
Future<bool> confirmDeleteSongShow(BuildContext context, SongShow show) => confirmDelete(
  context,
  title: 'Delete "${show.name}"?',
  message: 'Its timeline goes with it. The banks and chases it used stay in the project, and the song file is untouched.',
);
