part of 'live_grid_view.dart';

/// The Live tab's Mixer: one channel strip per lane, like a console. Each
/// strip lists its lane's clips (NOW / NEXT marked), with the lane's Amount
/// fader, rate and stop under it. The master section on the right is the
/// Grid's (GO, Main, Freeze, Stop all, Blackout).
class LiveMixerView extends ConsumerWidget {
  const LiveMixerView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(liveEngineProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= liveTabletBreakpoint) {
          return const Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _MixerStrips()),
              SizedBox(width: 240, child: _SidePanel()),
            ],
          );
        }
        return const _PhoneMixer();
      },
    );
  }
}

/// Saves what every lane runs now as a new Grid row. A Level lane that is
/// stopped goes in with the clip it last ran: without it the heads (and
/// dimmer pars) would stay dark when the row is played back.
Future<void> _saveMixAsScene(BuildContext context, WidgetRef ref) async {
  final l = context.l10n;
  final grid = ref.read(liveGridProvider);
  final engine = ref.read(liveEngineProvider);
  final running = ref.read(liveStatusProvider).running;
  final clips = <String, LiveClip>{for (final e in running.entries) e.key: ?grid.clipAt(e.key, e.value)};
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (clips.isEmpty) {
    messenger?.showSnackBar(SnackBar(content: Text(l.liveMixNothing)));
    return;
  }
  final addedLevel = <String>[];
  var darkLevel = false;
  for (final lane in grid.lanes) {
    if (lane.kind != LiveLaneKind.level || clips.containsKey(lane.id)) continue;
    final row = engine.lastRowOf(lane.id);
    final clip = row == null ? null : grid.clipAt(lane.id, row);
    if (clip == null) {
      darkLevel = true;
      continue;
    }
    clips[lane.id] = clip;
    addedLevel.add(clip.name);
  }
  final name = await _askName(context, l.liveMixSave, 'Mix ${grid.rows.length + 1}');
  if (name == null || name.trim().isEmpty) return;
  ref.read(liveGridProvider.notifier).addRowWith(name.trim(), clips);
  final saved = l.liveMixSaved(name.trim());
  final note = addedLevel.isNotEmpty
      ? '\n${l.liveMixLevelAdded(addedLevel.join(', '))}'
      : (darkLevel ? '\n${l.liveMixNoLevel}' : '');
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$saved$note')));
}

class _MixerStrips extends ConsumerWidget {
  const _MixerStrips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final lanes = ref.watch(liveGridProvider.select((g) => g.lanes));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(l.liveViewMixer, style: const TextStyle(color: AppColors.textDim, fontSize: 11, letterSpacing: 0.8)),
              const Spacer(),
              TextButton.icon(
                key: const ValueKey('live-mix-save'),
                onPressed: () => _saveMixAsScene(context, ref),
                icon: const Icon(Icons.bookmark_add_outlined),
                label: Text(l.liveMixSave),
              ),
              const SizedBox(width: 4),
              IconButton.outlined(
                tooltip: l.liveAddLane,
                onPressed: () => _addLane(context, ref),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: lanes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => SizedBox(width: 200, child: _MixerStrip(laneId: lanes[i].id)),
            ),
          ),
        ],
      ),
    );
  }
}

/// One lane as a channel strip.
class _MixerStrip extends ConsumerWidget {
  final String laneId;
  const _MixerStrip({required this.laneId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final grid = ref.watch(liveGridProvider);
    final lane = grid.lane(laneId);
    if (lane == null) return const SizedBox.shrink();
    final status = ref.watch(liveStatusProvider);
    final rows = [
      for (var row = 0; row < grid.rows.length; row++)
        if (grid.clipAt(lane.id, row) != null) row,
    ];
    final runningRow = status.running[lane.id];
    final nowClip = runningRow == null ? null : grid.clipAt(lane.id, runningRow);
    final hasFader =
        lane.kind == LiveLaneKind.moves || lane.kind == LiveLaneKind.colors || lane.kind == LiveLaneKind.level;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: runningRow != null ? AppColors.accent2 : AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final top = <Widget>[
              _LaneHeader(lane: lane),
              const SizedBox(height: 6),
              Text(
                nowClip == null ? l.liveMixIdle : '${l.liveMixNow} · ${nowClip.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: nowClip == null ? AppColors.textFaint : AppColors.accent2,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
            ];
            final clips = <Widget>[
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: SizedBox(
                    height: 72,
                    child: _ClipCell(lane: lane, row: row),
                  ),
                ),
              // New clip in the first empty row (or a new one).
              OutlinedButton.icon(
                onPressed: () async {
                  var row = 0;
                  while (row < grid.rows.length && grid.clipAt(lane.id, row) != null) {
                    row++;
                  }
                  if (row >= grid.rows.length) {
                    ref.read(liveGridProvider.notifier).addRow('${grid.rows.length + 1}');
                  }
                  await _editClip(context, ref, lane, row);
                },
                icon: const Icon(Icons.add, size: 16),
                label: Text(l.liveNewClip),
              ),
            ];
            final bottom = <Widget>[
              if (hasFader) ...[const SizedBox(height: 6), _AmountFader(lane: lane, running: runningRow != null)],
              const SizedBox(height: 6),
              _LaneFooter(lane: lane),
            ];
            // Too short to pin the fader (phone held sideways): scroll it all.
            if (constraints.maxHeight < 320) {
              return ListView(children: [...top, ...clips, ...bottom]);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...top,
                Expanded(child: ListView(children: clips)),
                ...bottom,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The lane's Amount: Moves size, Colors brightness, Level output.
class _AmountFader extends ConsumerWidget {
  final LiveLane lane;
  final bool running;
  const _AmountFader({required this.lane, required this.running});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final label = switch (lane.kind) {
      LiveLaneKind.moves => l.liveAmountSize,
      LiveLaneKind.colors => l.liveAmountBrightness,
      _ => l.liveAmountLevel,
    };
    // It scales what the lane plays: with nothing running it only presets.
    final fader = Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textDim, fontSize: 11),
          ),
        ),
        Expanded(
          child: Slider(
            key: ValueKey('live-amount-${lane.id}'),
            value: lane.amount.clamp(0.0, 1.0),
            onChanged: (v) => ref.read(liveGridProvider.notifier).updateLane(lane.copyWith(amount: v)),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '${(lane.amount * 100).round()}%',
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
    if (running) return fader;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Opacity(opacity: 0.45, child: fader),
        Text(
          l.liveAmountIdle,
          key: ValueKey('live-amount-idle-${lane.id}'),
          maxLines: 2,
          style: const TextStyle(color: AppColors.textFaint, fontSize: 10),
        ),
      ],
    );
  }
}

/// Phone: one strip at a time, swiped sideways, the launch bar under it.
class _PhoneMixer extends ConsumerWidget {
  const _PhoneMixer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final lanes = ref.watch(liveGridProvider.select((g) => g.lanes));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(l.liveMixSwipe, style: const TextStyle(color: AppColors.textDim, fontSize: 11)),
              ),
              TextButton.icon(
                key: const ValueKey('live-mix-save'),
                onPressed: () => _saveMixAsScene(context, ref),
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: Text(l.liveMixSave),
              ),
            ],
          ),
        ),
        Expanded(
          child: PageView(
            controller: PageController(viewportFraction: 0.86),
            padEnds: false,
            children: [
              for (final lane in lanes)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 0, 8),
                  child: _MixerStrip(laneId: lane.id),
                ),
            ],
          ),
        ),
        const _PhoneLaunchBar(),
      ],
    );
  }
}
