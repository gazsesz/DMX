import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/artnet_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../../l10n/l10n.dart';

/// The node's reachability, in the top-right corner of every screen.
///
/// The point is that you never have to go and press Test: the watchdog in
/// [ConnectionStatusNotifier] polls on its own, and this just renders what
/// it found. Green means an ArtPollReply actually came back; red with an
/// exclamation mark means it didn't, which is the one state worth spotting
/// from across a stage.
///
/// Tapping it re-polls immediately and reports the detail in a snackbar —
/// handy after moving the tablet or power-cycling the node.
class NodeStatusAction extends ConsumerStatefulWidget {
  const NodeStatusAction({super.key});

  @override
  ConsumerState<NodeStatusAction> createState() => _NodeStatusActionState();
}

class _NodeStatusActionState extends ConsumerState<NodeStatusAction> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    await ref.read(connectionStatusProvider.notifier).testConnection();
    if (!mounted) return;
    setState(() => _retrying = false);
    final status = ref.read(connectionStatusProvider);
    final settings = ref.read(artNetSettingsProvider);
    final String message;
    if (status.demo) {
      message = context.l10n.wDemoModeNothingIs;
    } else if (status.unverified) {
      message = context.l10n.wSendingSacnToThe;
    } else if (status.success) {
      message = context.l10n.wRepliedFromInMs(settings.deviceName, settings.host, status.latency?.inMilliseconds ?? 0);
    } else {
      message = status.error ?? context.l10n.wNoReplyFrom(settings.host);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(connectionStatusProvider);
    final settings = ref.watch(artNetSettingsProvider);

    late final Color color;
    late final IconData icon;
    late final String label;
    late final String tooltip;

    if (status.demo) {
      color = AppColors.accent;
      icon = Icons.play_circle_outline;
      label = 'DEMO';
      tooltip = context.l10n.wDemoModeNoPackets;
    } else if (status.unverified && status.success) {
      color = AppColors.accent2;
      icon = Icons.cell_tower;
      label = 'sACN';
      tooltip = context.l10n.wStreamingSacnE131;
    } else if (status.success) {
      color = AppColors.success;
      icon = Icons.check_circle;
      label = context.l10n.wMs2(status.latency?.inMilliseconds ?? 0);
      tooltip = context.l10n.wOnlineAt(settings.deviceName, settings.host);
    } else if (!status.attempted) {
      // Nothing has come back yet — the very first poll is still in flight.
      color = AppColors.textFaint;
      icon = Icons.circle_outlined;
      label = '···';
      tooltip = context.l10n.wLookingForTheNode;
    } else {
      // No text beside it: the icon already *is* an exclamation mark, and
      // a "!" label next to it just read as a stutter.
      color = AppColors.danger;
      icon = Icons.error;
      label = '';
      tooltip = status.error ?? context.l10n.wNoReplyFrom(settings.host);
    }

    return Tooltip(
      message: context.l10n.wTapToReCheck(tooltip),
      child: InkWell(
        onTap: _retrying ? null : _retry,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_retrying || !status.attempted)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                )
              else
                Icon(icon, size: 16, color: color),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 5),
                Text(
                  label,
                  style: appMonoStyle(fontSize: 11, color: color).copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
