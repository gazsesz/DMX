import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/song/analyse_file.dart';
import '../../core/song/song_analysis.dart';
import '../../core/song/song_generator.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../models/bank.dart';
import '../../models/song_show.dart';
import '../../state/bank_providers.dart';
import '../../state/fixture_group_providers.dart';
import '../../state/layer_providers.dart';
import '../../state/song_show_providers.dart';
import 'song_timeline.dart';
import '../../l10n/l10n.dart';
import '../../l10n/labels.dart';

/// Suggests a program for the song: it analyses the audio (tempo, beat grid,
/// sections), then builds cues from the chosen banks in the chosen style.
/// Nothing is written to the show until one of the two buttons is pressed, and
/// the result opens in the editor like any hand-made show.
class SongAutoScreen extends ConsumerStatefulWidget {
  const SongAutoScreen({super.key, required this.showId, this.analyse = analyseAudioFile});

  final String showId;

  /// The analysis step, swappable so tests don't need an audio engine.
  final Future<SongAnalysis> Function(String path) analyse;

  @override
  ConsumerState<SongAutoScreen> createState() => _SongAutoScreenState();
}

class _SongAutoScreenState extends ConsumerState<SongAutoScreen> {
  SongAnalysis? _analysis;
  Object? _error;
  late SongGeneratorOptions _options;
  List<String> _movePool = const [];

  SongShow? get _show {
    for (final s in ref.read(songShowsProvider)) {
      if (s.id == widget.showId) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final layers = ref.read(layersProvider);
    final banks = ref.read(banksProvider);
    _options = SongGeneratorOptions(
      seed: math.Random().nextInt(9000) + 1000,
      lookLayerId: layers.first.id,
      moveLayerId: layers.length > 1 ? layers[1].id : null,
      lookPools: suggestLookPools(banks),
      movePools: suggestMovePools(banks),
      groupIds: _show?.groupIds ?? const [],
    );
    _movePool = suggestMovePools(banks)[SongSectionKind.drop] ?? const [];
    _run();
  }

  Future<void> _run() async {
    final path = _show?.audio?.path;
    if (path == null) {
      setState(() => _error = const _NoSongLinked());
      return;
    }
    setState(() {
      _analysis = null;
      _error = null;
    });
    try {
      final a = await widget.analyse(path);
      if (mounted) setState(() => _analysis = a);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  SongGeneratorOptions get _effective => _options.copyWith(
    movePools: {for (final k in SongSectionKind.values) k: _options.style.movementKinds.contains(k) ? _movePool : const <String>[]},
  );

  Future<bool> _confirmReplace(SongShow show, {required bool cues}) async {
    final hasWork = cues ? (show.cues.isNotEmpty || show.sections.isNotEmpty) : show.sections.isNotEmpty;
    if (!hasWork) return true;
    return confirmDelete(
      context,
      title: context.l10n.songReplaceWhatIsOn,
      message: cues
          ? context.l10n.songCuesAndSectionsAre(show.cues.length, show.sections.length)
          : context.l10n.songTheSectionsAreReplaced,
      confirmLabel: context.l10n.songReplace,
    );
  }

  Future<void> _apply({required bool full}) async {
    final show = _show;
    final analysis = _analysis;
    if (show == null || analysis == null) return;
    if (!await _confirmReplace(show, cues: full) || !mounted) return;
    final next = full
        ? generateSongShow(base: show, analysis: analysis, options: _effective)
        : applyAnalysis(show, analysis);
    ref.read(songShowsProvider.notifier).upsert(next);
    updateRunningSongShow(ref.read, next);
    Navigator.of(context).pop(true);
  }

  Future<void> _editPool(String title, List<String> current, List<Bank> candidates, void Function(List<String>) onDone) async {
    final chosen = {...current};
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 340,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final b in candidates)
                  CheckboxListTile(
                    dense: true,
                    title: Text(b.name),
                    value: chosen.contains(b.id),
                    onChanged: (v) => setLocal(() => v == true ? chosen.add(b.id) : chosen.remove(b.id)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.commonCancel)),
            FilledButton(onPressed: () => Navigator.pop(context, chosen.toList()), child: Text(context.l10n.commonDone)),
          ],
        ),
      ),
    );
    if (result != null && mounted) setState(() => onDone(result));
  }

  String _names(List<String> ids, List<Bank> banks) {
    final byId = {for (final b in banks) b.id: b.name};
    final names = [for (final id in ids) if (byId[id] != null) byId[id]!];
    return names.isEmpty ? 'none' : names.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final banks = ref.watch(banksProvider);
    final layers = ref.watch(layersProvider);
    final groups = ref.watch(fixtureGroupsProvider);
    final analysis = _analysis;
    final lightBanks = [for (final b in banks) if (!b.isMovementFx) b];
    final fxBanks = [for (final b in banks) if (b.isMovementFx) b];
    final kinds = analysis == null ? <SongSectionKind>[] : ({for (final s in analysis.sections) s.kind}.toList()
      ..sort((a, b) => a.index.compareTo(b.index)));
    final moveKinds = _options.style.movementKinds;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.songAutoProgram)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (_error != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.error_outline, color: AppColors.danger),
                title: Text(_error is _NoSongLinked ? context.l10n.songLinkASongFile : '$_error'),
                trailing: TextButton(onPressed: _run, child: Text(context.l10n.songRetry)),
              ),
            )
          else if (analysis == null)
            Card(
              child: ListTile(
                leading: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                title: Text(context.l10n.songListeningToTheSong),
                subtitle: Text(context.l10n.songTempoBeatGridAnd),
              ),
            )
          else ...[
            _Summary(analysis: analysis),
            const SizedBox(height: 12),
            _Heading(context.l10n.songStyle),
            Wrap(
              spacing: 8,
              children: [
                for (final s in SongStyle.values)
                  ChoiceChip(
                    key: ValueKey('style-${s.name}'),
                    label: Text(s.label),
                    selected: s == _options.style,
                    onSelected: (_) => setState(() => _options = _options.copyWith(style: s)),
                  ),
              ],
            ),
            Text(_options.style.trDescription(context.l10n), style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(context.l10n.songRestlessness),
                Expanded(
                  child: Slider(
                    key: const ValueKey('audacity'),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '${_options.audacity}',
                    value: _options.audacity.toDouble(),
                    onChanged: (v) => setState(() => _options = _options.copyWith(audacity: v.round())),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Text(context.l10n.songSeed(_options.seed), style: const TextStyle(fontSize: 12, color: AppColors.textDim)),
                IconButton(
                  key: const ValueKey('reroll'),
                  icon: const Icon(Icons.casino_outlined),
                  tooltip: context.l10n.songAnotherArrangement,
                  onPressed: () =>
                      setState(() => _options = _options.copyWith(seed: math.Random().nextInt(9000) + 1000)),
                ),
              ],
            ),
            _Heading(context.l10n.dashLayersHeader),
            Row(
              children: [
                const Text('Looks on '),
                DropdownButton<String>(
                  value: layers.any((l) => l.id == _options.lookLayerId) ? _options.lookLayerId : layers.first.id,
                  items: [for (final l in layers) DropdownMenuItem(value: l.id, child: Text(l.name))],
                  onChanged: (v) => setState(() => _options = _options.copyWith(lookLayerId: v)),
                ),
                const SizedBox(width: 16),
                const Text('Movement on '),
                DropdownButton<String?>(
                  key: const ValueKey('move-layer'),
                  value: layers.any((l) => l.id == _options.moveLayerId) ? _options.moveLayerId : null,
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('none')),
                    for (final l in layers) DropdownMenuItem<String?>(value: l.id, child: Text(l.name)),
                  ],
                  onChanged: (v) => setState(() => _options = v == null
                      ? _options.copyWith(clearMoveLayer: true)
                      : _options.copyWith(moveLayerId: v)),
                ),
              ],
            ),
            _Heading(context.l10n.songBanksToUse),
            for (final kind in kinds)
              ListTile(
                key: ValueKey('pool-${kind.name}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Container(width: 6, height: 28, color: sectionColor(kind)),
                title: Text(sectionKindLabel(kind, context.l10n)),
                subtitle: Text(_names(_options.lookPools[kind] ?? const [], banks), maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: () => _editPool(
                  context.l10n.songKindLooks(sectionKindLabel(kind, context.l10n)),
                  _options.lookPools[kind] ?? const [],
                  lightBanks,
                  (ids) => _options = _options.copyWith(lookPools: {..._options.lookPools, kind: ids}),
                ),
              ),
            if (_options.moveLayerId != null && moveKinds.isNotEmpty)
              ListTile(
                key: const ValueKey('pool-move'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.open_with, size: 20),
                title: Text(context.l10n.songMovementKinds(moveKinds.map((k) => sectionKindLabel(k, context.l10n).toLowerCase()).join(', '))),
                subtitle: Text(fxBanks.isEmpty ? context.l10n.songNoMovementFxBanks : _names(_movePool, banks)),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: fxBanks.isEmpty
                    ? null
                    : () => _editPool(context.l10n.songMovementBanks, _movePool, fxBanks, (ids) => _movePool = ids),
              ),
            if (groups.isNotEmpty) ...[
              _Heading(context.l10n.scFixtures),
              Wrap(
                spacing: 8,
                children: [
                  for (final g in groups)
                    FilterChip(
                      label: Text(g.name),
                      selected: _options.groupIds.contains(g.id),
                      onSelected: (on) => setState(() => _options = _options.copyWith(
                        groupIds: on ? [..._options.groupIds, g.id] : [for (final id in _options.groupIds) if (id != g.id) id],
                      )),
                    ),
                ],
              ),
              Text(
                context.l10n.songSavedWithTheShow,
                style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('apply-analysis'),
                    onPressed: () => _apply(full: false),
                    child: Text(context.l10n.songTempoAndSectionsOnly),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('generate-show'),
                    onPressed: () => _apply(full: true),
                    child: Text(context.l10n.songGenerateShow),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 4),
    child: Text(
      text,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint, letterSpacing: 1),
    ),
  );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.analysis});
  final SongAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final unsure = analysis.tempoConfidence < 0.25;
    final bars = analysis.barLevel.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.songBpmGridMsBars(analysis.bpm.toStringAsFixed(1), analysis.beatOffsetMs, bars, analysis.sections.length),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (unsure)
              Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  context.l10n.songNotSureAboutThe,
                  style: TextStyle(fontSize: 11, color: AppColors.accent),
                ),
              ),
            const SizedBox(height: 8),
            if (analysis.sections.isEmpty)
              Text(context.l10n.songNoSectionsFoundThe, style: TextStyle(fontSize: 12))
            else
              SizedBox(
                height: 26,
                child: Row(
                  children: [
                    for (final s in analysis.sections)
                      Expanded(
                        flex: s.lengthBeats.round(),
                        child: Container(
                          margin: const EdgeInsets.only(right: 2),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: sectionColor(s.kind), borderRadius: BorderRadius.circular(4)),
                          child: Text(
                            sectionKindLabel(s.kind, context.l10n),
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The "no song file linked" state, worded at build time (the message is
/// set from initState, before localizations can be read).
class _NoSongLinked {
  const _NoSongLinked();
}
