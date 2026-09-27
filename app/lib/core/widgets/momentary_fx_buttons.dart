import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/momentary_fx_providers.dart';
import '../theme/app_colors.dart';

/// How a momentary button is drawn, and how readily the strip gives it up.
class MomentaryFxStyle {
  final IconData icon;
  final Color color;

  /// Lower goes first — see [dockItemsThatFit]. These sit after everything
  /// else the strip is willing to drop.
  final int giveUpAt;

  const MomentaryFxStyle(this.icon, this.color, this.giveUpAt);
}

/// In the order they're laid out, which is also the order you reach for them:
/// strobe first, and last to be given up when the screen is narrow.
const momentaryFxStyles = <MomentaryFx, MomentaryFxStyle>{
  MomentaryFx.strobe: MomentaryFxStyle(Icons.flash_on, AppColors.accent, 5),
  // White, because that's what a blinder does.
  MomentaryFx.blinder: MomentaryFxStyle(Icons.wb_sunny, AppColors.text, 4),
  MomentaryFx.freeze: MomentaryFxStyle(Icons.ac_unit, AppColors.accent2, 3),
};

/// The look of a dock control: a labelled icon in a bordered tile, lit while
/// it's the active one.
///
/// Its own widget because the dock has two kinds of button wearing it — the
/// ones you tap, and the momentary ones you hold — and they can't share an
/// InkWell: see [MomentaryFxButton].
class DockButtonFace extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool active;
  final bool enabled;

  const DockButtonFace({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.active = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final tint = enabled ? color : AppColors.textFaint;
    return Container(
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
    );
  }
}

/// A dock button that lives only while it's held: pressing engages the
/// effect, letting go puts the previous look straight back.
///
/// A raw [Listener] rather than an [InkWell] or a [GestureDetector] on
/// purpose. A tap gesture gives its pointer up as soon as the finger drifts
/// past the touch slop, which on a tablet held one-handed would drop a strobe
/// mid-hold; pointer events keep going to whatever the finger went *down* on
/// until it comes up again, wherever it wandered in between.
class MomentaryFxButton extends ConsumerStatefulWidget {
  final MomentaryFx fx;
  final IconData icon;
  final Color color;

  const MomentaryFxButton({super.key, required this.fx, required this.icon, required this.color});

  @override
  ConsumerState<MomentaryFxButton> createState() => _MomentaryFxButtonState();
}

class _MomentaryFxButtonState extends ConsumerState<MomentaryFxButton> {
  /// Held rather than read back out of the provider, so [dispose] can end the
  /// effect without touching a `ref` that is on its way out.
  MomentaryFxController? _controller;
  bool _down = false;

  void _press() {
    if (_down) return;
    _down = true;
    final controller = ref.read(momentaryFxProvider.notifier);
    _controller = controller;
    controller.press(widget.fx);
  }

  void _release() {
    if (!_down) return;
    _down = false;
    _controller?.release(widget.fx);
  }

  @override
  void dispose() {
    // The strip gives controls up as the screen narrows, and a rotation can
    // take this button off screen with a finger still on it. An effect nobody
    // is holding any more is an effect nobody can stop.
    if (_down) _controller?.releaseLater(widget.fx);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final held = ref.watch(momentaryFxProvider).contains(widget.fx);
    return Listener(
      onPointerDown: (_) => _press(),
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: DockButtonFace(
        icon: widget.icon,
        label: widget.fx.label,
        color: widget.color,
        active: held,
      ),
    );
  }
}
