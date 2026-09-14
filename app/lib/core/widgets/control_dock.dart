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

/// The live controls that are worth reaching from *any* screen: what's
/// running (and a way to stop it), beat sync with its rate, and blackout.
///
/// Everything here is backed by app-wide state, so the dock never disagrees
/// with the Dashboard — tempo/fade stay on the Dashboard, since those are
/// programming controls rather than things you grab mid-show.
class ControlDock extends ConsumerWidget {
  final ControlDockPosition position;

  const ControlDock({super.key, required this.position});

  bool get _vertical => position == ControlDockPosition.right;

  /// Restarts whatever played last. Reports back, because the common
  /// failure — no node on the network — is silent otherwise.
  Future<void> _resume(BuildContext context, WidgetRef ref) async {
    final message = await resumeLastPlayed(ref.read);
    if (!context.mounted || message.startsWith('Started')) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setBeatSync(BuildContext context, WidgetRef ref, bool value) async {
    final error = await ref.read(beatSyncEnabledProvider.notifier).setEnabled(value);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nowPlaying = ref.watch(nowPlayingProvider);
    final beatSync = ref.watch(beatSyncEnabledProvider);
    final lastPlayed = ref.watch(lastPlayedProvider);
    final tempo = ref.watch(tempoProvider);
    // Only meaningful while a Smart Program is the thing running — the
    // stream keeps its last value after one stops.
    final zone = nowPlaying?.kind == PlaybackKind.smartProgram
        ? ref.watch(smartProgramStatusProvider).valueOrNull
        : null;

    final children = <Widget>[
      _NowPlayingChip(nowPlaying: nowPlaying, zone: zone, vertical: _vertical),
      if (nowPlaying == null)
        _DockButton(
          icon: Icons.play_arrow_rounded,
          label: 'Start',
          color: AppColors.success,
          enabled: lastPlayed != null,
          onTap: () => _resume(context, ref),
        )
      else
        _DockButton(
          icon: Icons.stop_rounded,
          label: 'Stop',
          color: AppColors.accent,
          onTap: () => stopPlayback(ref.read),
        ),
      _DockButton(
        icon: Icons.mic_none,
        label: 'Beat',
        color: AppColors.accent2,
        active: beatSync,
        onTap: () => _setBeatSync(context, ref, !beatSync),
      ),
      if (beatSync)
        SegmentedButton<BeatRate>(
          segments: [for (final rate in BeatRate.values) ButtonSegment(value: rate, label: Text(rate.label))],
          selected: {ref.watch(beatRateProvider)},
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onSelectionChanged: (selection) => ref.read(beatRateProvider.notifier).state = selection.first,
        ),
      // Greyed out while Flash is the beat rate — Flash snaps by
      // definition, so it forces the fade to zero and auto-fade has
      // nothing to do. Showing it dimmed rather than hiding it keeps the
      // toggle's own state visible.
      _DockButton(
        icon: Icons.blur_on,
        label: 'AutoFade',
        color: AppColors.accent2,
        active: tempo.autoFade,
        enabled: !(beatSync && ref.watch(beatRateProvider) == BeatRate.flash),
        onTap: () => ref.read(tempoProvider.notifier).setAutoFade(!tempo.autoFade),
      ),
      _DockButton(
        icon: Icons.power_settings_new,
        label: 'Blackout',
        color: AppColors.danger,
        onTap: () => blackoutEverything(ref.read),
      ),
    ];

    final content = _vertical
        ? Column(mainAxisSize: MainAxisSize.min, children: [
            for (final child in children) Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: child),
          ])
        : Row(children: [
            for (final child in children) Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: child),
          ]);

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
          child: _vertical
              ? SingleChildScrollView(child: content)
              : SingleChildScrollView(scrollDirection: Axis.horizontal, child: content),
        ),
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
        width: vertical ? 56 : 96,
        child: Text(
          'Idle',
          textAlign: TextAlign.center,
          style: appMonoStyle(fontSize: 10.5, color: AppColors.textFaint),
        ),
      );
    }
    final status = zone;
    return SizedBox(
      width: vertical ? 56 : 150,
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
          tooltip: dock.visible ? 'Hide control dock' : 'Show control dock',
          icon: Icon(
            dock.visible ? Icons.dashboard_customize : Icons.dashboard_customize_outlined,
            color: dock.visible ? AppColors.accent : null,
          ),
          onPressed: () => ref.read(controlDockProvider.notifier).toggleVisible(),
        ),
      ],
    );
  }
}
