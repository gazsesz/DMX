import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/dashboard/live_stage_view.dart';
import '../../models/control_dock_prefs.dart';
import '../../state/audio_providers.dart';
import '../../state/control_dock_providers.dart';
import '../../state/playback_providers.dart';
import '../../state/tempo_providers.dart';
import '../playback/chase_player.dart';
import '../playback/smart_program_player.dart';
import '../remote/trigger_actions.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'control_panel.dart';
import 'dock_layout.dart';
import 'master_fader.dart';

/// The live controls that are worth reaching from *any* screen: what's
/// running (and a way to stop it), beat sync with its rate, blackout — and
/// the button that opens the full tempo panel.
///
/// Everything here is backed by app-wide state, so the dock never disagrees
/// with the Dashboard.
class ControlDock extends ConsumerWidget {
  final ControlDockPosition position;

  const ControlDock({super.key, required this.position});

  bool get _vertical => position == ControlDockPosition.right;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controls = _DockControls(vertical: _vertical);

    return Material(
      color: AppColors.panel2,
      child: SafeArea(
        top: false,
        left: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              top: _vertical ? BorderSide.none : const BorderSide(color: AppColors.border),
              left: _vertical ? const BorderSide(color: AppColors.border) : BorderSide.none,
            ),
          ),
          // Only the side dock scrolls, and only along its own length. The
          // bottom strip lays itself out to fit instead — a control you
          // have to swipe sideways for is a control you don't have.
          child: _vertical ? SingleChildScrollView(child: controls) : controls,
        ),
      ),
    );
  }
}

/// The dock with its panel open: the tempo and beat controls, plus the same
/// basic controls the closed strip carries, stacked down a rail beside
/// them.
///
/// They stay on screen on purpose — opening the tempo panel used to bury
/// Stop, Blackout and the master fader under a full-width sheet, which is
/// the moment you're most likely to want them. The rail is also what says
/// the thing that opened is the *dock*: it's the same row of buttons,
/// stood on its side.
class ExpandedControlDock extends ConsumerWidget {
  const ExpandedControlDock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.panel,
      elevation: 12,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Column(
        children: [
          const _PanelHeader(),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Expanded(child: ControlPanel()),
                const VerticalDivider(width: 1, color: AppColors.border),
                Container(
                  color: AppColors.panel2,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: const SingleChildScrollView(
                    // The panel beside it already carries the beat rate, so
                    // the rail leaves that one out rather than showing it
                    // twice.
                    child: _DockControls(vertical: true, showBeatRate: false),
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

class _PanelHeader extends ConsumerWidget {
  const _PanelHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
      child: Row(
        children: [
          const Icon(Icons.tune, size: 16, color: AppColors.accent),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Control dock',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.text),
            ),
          ),
          IconButton(
            tooltip: 'Close the panel',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 20, color: AppColors.textDim),
            onPressed: () => ref.read(controlDockProvider.notifier).collapse(),
          ),
        ],
      ),
    );
  }
}

/// The dock's controls, laid out along a row (the closed bottom strip) or
/// down a column (the right-hand dock, and the open panel's rail).
class _DockControls extends ConsumerWidget {
  final bool vertical;
  final bool showBeatRate;

  const _DockControls({required this.vertical, this.showBeatRate = true});

  /// Restarts whatever played last. Reports back, because the common
  /// failure — no node on the network — is silent otherwise.
  Future<void> _resume(BuildContext context, WidgetRef ref) async {
    final message = await resumeLastPlayed(ref.read);
    if (!context.mounted || message.startsWith('Started')) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setBeatSync(BuildContext context, WidgetRef ref, bool value) async {
    final error = await ref.read(beatSyncEnabledProvider.notifier).setEnabled(value);
    if (error != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      }
      return;
    }
    // Arming beat sync only changes what's already playing if it's re-fired
    // — the panel's own switch has always done this, the dock's didn't.
    await restartActiveTrigger(ref.read);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nowPlaying = ref.watch(nowPlayingProvider);
    final beatSync = ref.watch(beatSyncEnabledProvider);
    final lastPlayed = ref.watch(lastPlayedProvider);
    final tempo = ref.watch(tempoProvider);
    final expanded = ref.watch(controlDockProvider).expanded;
    // Only meaningful while a Smart Program is the thing running — the
    // stream keeps its last value after one stops.
    final zone = nowPlaying?.kind == PlaybackKind.smartProgram
        ? ref.watch(smartProgramStatusProvider).valueOrNull
        : null;

    // Width is declared alongside each control rather than measured: the
    // strip has to know what fits *before* laying anything out, and every
    // one of these is a fixed size anyway.
    final items = <_DockItem>[
      _DockItem(
        _NowPlayingChip(nowPlaying: nowPlaying, zone: zone, vertical: vertical),
        vertical ? 62 : (nowPlaying == null ? 96 : 150),
      ),
      _DockItem(
        nowPlaying == null
            ? _DockButton(
                icon: Icons.play_arrow_rounded,
                label: 'Start',
                color: AppColors.success,
                enabled: lastPlayed != null,
                onTap: () => _resume(context, ref),
              )
            : _DockButton(
                icon: Icons.stop_rounded,
                label: 'Stop',
                color: AppColors.accent,
                onTap: () => stopPlayback(ref.read),
              ),
        _dockButtonWidth,
      ),
      _DockItem(
        _DockButton(
          icon: Icons.mic_none,
          label: 'Beat',
          color: AppColors.accent2,
          active: beatSync,
          onTap: () => _setBeatSync(context, ref, !beatSync),
        ),
        _dockButtonWidth,
      ),
      if (beatSync && showBeatRate)
        // First to go when the strip is short of room: it's a setting
        // rather than a control you grab, and the panel has it too.
        _DockItem(const _BeatRateControl(), _dockButtonWidth, giveUpAt: 1),
      // Greyed out while Flash is the beat rate — Flash snaps by
      // definition, so it forces the fade to zero and auto-fade has
      // nothing to do. Showing it dimmed rather than hiding it keeps the
      // toggle's own state visible.
      _DockItem(
        _DockButton(
          icon: Icons.blur_on,
          label: 'AutoFade',
          color: AppColors.accent2,
          active: tempo.autoFade,
          enabled: !(beatSync && ref.watch(beatRateProvider) == BeatRate.flash),
          onTap: () => ref.read(tempoProvider.notifier).setAutoFade(!tempo.autoFade),
        ),
        _dockButtonWidth,
        giveUpAt: 2,
      ),
      // Sits next to Blackout on purpose: Blackout is this taken to zero
      // for a moment, and grouping them says so.
      _DockItem(
        MasterFader(vertical: vertical, width: vertical ? 62 : 124),
        vertical ? 62 : 124,
        giveUpAt: 3,
      ),
      _DockItem(
        _DockButton(
          icon: Icons.power_settings_new,
          label: 'Blackout',
          color: AppColors.danger,
          onTap: () => blackoutEverything(ref.read),
        ),
        _dockButtonWidth,
      ),
      // Part of the row rather than a tab hanging off the dock's outer
      // edge: the old handle sat at the far end of the screen, nowhere
      // near the controls, and read as belonging to the page instead.
      _DockItem(
        _DockButton(
          icon: expanded ? Icons.keyboard_arrow_down : Icons.tune,
          label: expanded ? 'Close' : 'Tempo',
          color: AppColors.accent,
          active: expanded,
          onTap: () => ref.read(controlDockProvider.notifier).toggleExpanded(),
        ),
        _dockButtonWidth,
      ),
    ];

    if (vertical) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        for (final item in items)
          Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: item.widget),
      ]);
    }

    // Wrapping rather than scrolling sideways: see dock_layout.dart.
    return LayoutBuilder(
      builder: (context, constraints) {
        final keep = dockItemsThatFit(
          widths: [for (final item in items) item.width],
          dropOrder: _dropOrder(items),
          available: constraints.maxWidth,
        );
        return Wrap(
          spacing: dockItemSpacing,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [for (final i in keep) items[i].widget],
        );
      },
    );
  }

  /// The indices of the controls that may be given up, worst first.
  static List<int> _dropOrder(List<_DockItem> items) {
    final droppable = [
      for (var i = 0; i < items.length; i++)
        if (items[i].giveUpAt != null) i,
    ];
    droppable.sort((a, b) => items[a].giveUpAt!.compareTo(items[b].giveUpAt!));
    return droppable;
  }
}

const _dockButtonWidth = 62.0;

/// One control in the strip, with the width it occupies and how readily the
/// strip gives it up — null meaning never.
class _DockItem {
  final Widget widget;
  final double width;
  final int? giveUpAt;

  const _DockItem(this.widget, this.width, {this.giveUpAt});
}

/// Steps per beat, as a 2×2 block the width of a dock button.
///
/// It used to be a segmented button along the strip, which is four labels
/// wide and was a good part of why the strip ran off a narrow screen. The
/// panel still spells it out in full.
class _BeatRateControl extends ConsumerWidget {
  const _BeatRateControl();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(beatRateProvider);
    void select(BeatRate rate) => ref.read(beatRateProvider.notifier).state = rate;

    return SizedBox(
      width: 62,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final rate in BeatRate.values)
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => select(rate),
              child: Container(
                width: 29,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: rate == selected ? AppColors.accent2.withValues(alpha: 0.18) : AppColors.panel,
                  border: Border.all(
                    color: rate == selected ? AppColors.accent2 : AppColors.border,
                    width: rate == selected ? 2 : 1.5,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  rate.label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: rate == selected ? AppColors.accent2 : AppColors.textDim,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shows what's playing — the whole reason the dock is worth having on a
/// screen that isn't the Dashboard.
class _NowPlayingChip extends StatelessWidget {
  final NowPlaying? nowPlaying;

  /// Set only while a Smart Program is what's running — which of its zones
  /// is playing right now, and the tempo it's tracking.
  final SmartProgramStatus? zone;
  final bool vertical;

  const _NowPlayingChip({required this.nowPlaying, required this.zone, required this.vertical});

  static String _zoneLabel(SmartProgramStatus status) {
    if (status.isSilent) return 'Waiting for music';
    final name = switch (status.zone) {
      SmartProgramZone.faster => 'Faster',
      SmartProgramZone.slower => 'Slower',
      SmartProgramZone.base => 'Base',
    };
    final bpm = status.liveBpm;
    return bpm == null ? name : '$name · ${bpm.round()} BPM';
  }

  @override
  Widget build(BuildContext context) {
    final playing = nowPlaying;
    if (playing == null) {
      return SizedBox(
        width: vertical ? 62 : 96,
        child: Text(
          'Idle',
          textAlign: TextAlign.center,
          style: appMonoStyle(fontSize: 10.5, color: AppColors.textFaint),
        ),
      );
    }
    final status = zone;
    return SizedBox(
      width: vertical ? 62 : 150,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            switch (playing.kind) {
              PlaybackKind.bank => Icons.grid_view_outlined,
              PlaybackKind.chase => Icons.fast_forward_outlined,
              PlaybackKind.smartProgram => Icons.auto_graph,
            },
            size: 14,
            color: AppColors.accent,
          ),
          Text(
            playing.name,
            textAlign: TextAlign.center,
            maxLines: vertical ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.accent),
          ),
          if (status != null)
            Text(
              _zoneLabel(status),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: appMonoStyle(
                fontSize: 9,
                color: status.isSilent ? AppColors.textFaint : AppColors.accent2,
              ),
            ),
        ],
      ),
    );
  }
}


class _DockButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  const _DockButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.active = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final tint = enabled ? color : AppColors.textFaint;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: enabled ? onTap : null,
      child: Container(
        width: 62,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.18) : AppColors.panel,
          border: Border.all(color: active ? color : AppColors.border, width: active ? 2 : 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: tint),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: tint),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// The 2D Live Stage as a bottom strip, so the rig stays visible while
/// programming on any tab — the offline counterpart to actually watching the
/// lamps, and what makes Demo Mode useful.
class LiveStageDock extends StatelessWidget {
  const LiveStageDock({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.panel2,
      child: SafeArea(
        top: false,
        child: Container(
          height: 150,
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: const LiveStageView(),
        ),
      ),
    );
  }
}

/// App-bar toggles for the two docks — they sit next to Save on every main
/// screen so both can be shown/hidden from wherever you are.
class ControlDockAction extends ConsumerWidget {
  const ControlDockAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dock = ref.watch(controlDockProvider);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: dock.stageVisible ? 'Hide live stage' : 'Show live stage',
          icon: Icon(
            dock.stageVisible ? Icons.lightbulb : Icons.lightbulb_outline,
            color: dock.stageVisible ? AppColors.accent2 : null,
          ),
          onPressed: () => ref.read(controlDockProvider.notifier).toggleStageVisible(),
        ),
        IconButton(
          tooltip: dock.expanded ? 'Hide tempo controls' : 'Show tempo controls',
          icon: Icon(
            dock.expanded ? Icons.tune : Icons.tune_outlined,
            color: dock.expanded ? AppColors.accent : null,
          ),
          onPressed: () => ref.read(controlDockProvider.notifier).toggleExpanded(),
        ),
      ],
    );
  }
}
