import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A list card split in two: a wide Start/Stop zone down its left side and
/// the rest of the card, which opens the editor.
///
/// It used to be a 36 px circle inside a card whose every other pixel
/// opened the editor — on a tablet in a dark room, reaching for Start
/// landed in the editor more often than not. Now the whole left column,
/// edge to edge and top to bottom, is the toggle (a 52 px button in a
/// 76 px column, divided from the rest by a rule), so a thumb that is
/// roughly right is right.
class PlayToggleCard extends StatelessWidget {
  final bool active;

  /// The idle icon — what this card starts. Active always shows Stop.
  final IconData icon;

  /// The accent the card wears while running, and the colour drawn on it.
  final Color accent;
  final Color accentOn;

  final VoidCallback onToggle;
  final VoidCallback onOpen;

  /// The editor side's content: name, details, and its own trailing buttons.
  final Widget child;

  /// For tests to find the toggle.
  final Key? toggleKey;

  final String? toggleTooltip;

  const PlayToggleCard({
    super.key,
    required this.active,
    required this.icon,
    required this.accent,
    required this.accentOn,
    required this.onToggle,
    required this.onOpen,
    required this.child,
    this.toggleKey,
    this.toggleTooltip,
  });

  static const toggleWidth = 76.0;

  @override
  Widget build(BuildContext context) {
    final toggle = InkWell(
      key: toggleKey,
      onTap: onToggle,
      child: SizedBox(
        width: toggleWidth,
        child: Center(
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(shape: BoxShape.circle, color: active ? accent : AppColors.panel2),
            child: Icon(active ? Icons.stop_rounded : icon, color: active ? accentOn : accent, size: 28),
          ),
        ),
      ),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      color: active ? accent.withValues(alpha: 0.1) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: active ? accent : Colors.transparent, width: 1.5),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Semantics(
                button: true,
                label: active ? 'Stop' : 'Start',
                child: toggleTooltip == null ? toggle : Tooltip(message: toggleTooltip!, child: toggle),
              ),
            ),
            VerticalDivider(width: 1, thickness: 1, color: active ? accent.withValues(alpha: 0.4) : AppColors.panel2),
            Expanded(
              child: InkWell(
                onTap: onOpen,
                child: Padding(padding: const EdgeInsets.fromLTRB(12, 10, 4, 10), child: child),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
