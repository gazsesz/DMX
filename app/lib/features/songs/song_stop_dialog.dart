import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/song_show.dart';
import '../../l10n/l10n.dart';

/// How a Stop cue ends the layer.
class StopChoice {
  final bool blackout;
  final int fadeMs;

  const StopChoice({required this.blackout, this.fadeMs = SongCue.defaultStopFadeMs});
}

/// The fade lengths offered for a blackout, in milliseconds.
const stopFadeChoices = [0, 500, 1000, 2000, 4000];

String stopFadeLabel(BuildContext context, int ms) => ms == 0 ? context.l10n.songCut : '${ms / 1000} s';

/// Asks how a Stop should end: keep the last look on stage as it was (the
/// bank's last scene, or the scene), or fade the lights out. Returns null when
/// dismissed.
Future<StopChoice?> showStopDialog(BuildContext context, {StopChoice initial = const StopChoice(blackout: false)}) {
  return showDialog<StopChoice>(
    context: context,
    builder: (context) => _StopDialog(initial: initial),
  );
}

class _StopDialog extends StatefulWidget {
  const _StopDialog({required this.initial});
  final StopChoice initial;

  @override
  State<_StopDialog> createState() => _StopDialogState();
}

class _StopDialogState extends State<_StopDialog> {
  late bool _blackout = widget.initial.blackout;
  late int _fadeMs = widget.initial.fadeMs;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.songHowDoesItEnd),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Option(
            key: const ValueKey('stop-mode-hold'),
            selected: !_blackout,
            title: context.l10n.songKeepTheLastLook,
            subtitle: context.l10n.songTheBankSLast,
            onTap: () => setState(() => _blackout = false),
          ),
          _Option(
            key: const ValueKey('stop-mode-blackout'),
            selected: _blackout,
            title: context.l10n.commonBlackout,
            subtitle: context.l10n.songTheLightsFadeOut,
            onTap: () => setState(() => _blackout = true),
          ),
          if (_blackout) ...[
            const SizedBox(height: 8),
            Text(context.l10n.songFadeOutOver, style: TextStyle(fontSize: 12, color: AppColors.textDim)),
            Wrap(
              spacing: 6,
              children: [
                for (final ms in stopFadeChoices)
                  ChoiceChip(
                    key: ValueKey('stop-fade-$ms'),
                    label: Text(stopFadeLabel(context, ms)),
                    selected: ms == _fadeMs,
                    onSelected: (_) => setState(() => _fadeMs = ms),
                  ),
              ],
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.commonCancel)),
      FilledButton(
        key: const ValueKey('stop-mode-ok'),
        onPressed: () => Navigator.pop(context, StopChoice(blackout: _blackout, fadeMs: _fadeMs)),
        child: Text(context.l10n.wOk),
      ),
    ],
  );
}

class _Option extends StatelessWidget {
  const _Option({super.key, required this.selected, required this.title, required this.subtitle, required this.onTap});
  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? AppColors.accent2 : null),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
    onTap: onTap,
  );
}
