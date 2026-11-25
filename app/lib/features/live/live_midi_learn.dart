import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/midi/midi_input_message.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/l10n.dart';
import '../../state/live_midi_providers.dart';
import '../../state/live_providers.dart';
import '../../state/midi_control_providers.dart';

/// The Grid's MIDI button: lights up the learn mode, where a tap on a clip
/// (or a row button, GO, Stop) waits for the pad to bind to it.
class LiveMidiLearnButton extends ConsumerWidget {
  final bool compact;
  const LiveMidiLearnButton({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(liveMidiLearnProvider);
    return IconButton(
      key: const ValueKey('live-midi-learn'),
      tooltip: context.l10n.liveMidiLearn,
      isSelected: on,
      visualDensity: compact ? VisualDensity.compact : null,
      color: on ? AppColors.accent : null,
      icon: const Icon(Icons.piano_outlined),
      selectedIcon: const Icon(Icons.piano),
      onPressed: () => ref.read(liveMidiLearnProvider.notifier).state = !on,
    );
  }
}

/// The strip over the Grid / Mixer while learning: what to do, the 4×4
/// quick fill, and Done.
class LiveMidiLearnBanner extends ConsumerWidget {
  const LiveMidiLearnBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(liveMidiLearnProvider)) return const SizedBox.shrink();
    final l = context.l10n;
    return Container(
      key: const ValueKey('live-midi-banner'),
      width: double.infinity,
      color: AppColors.accent.withValues(alpha: 0.14),
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text(l.liveMidiLearnHint, style: const TextStyle(fontSize: 12)),
          OutlinedButton.icon(
            key: const ValueKey('live-midi-fill'),
            icon: const Icon(Icons.grid_view, size: 16),
            label: Text(l.liveMidiFill),
            onPressed: () => _fill(context, ref),
          ),
          FilledButton(
            onPressed: () => ref.read(liveMidiLearnProvider.notifier).state = false,
            child: Text(l.commonDone),
          ),
        ],
      ),
    );
  }

  Future<void> _fill(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    if (!_hasController(context, ref)) return;
    final first = await waitForPad(context, ref, l.liveMidiFill, l.liveMidiFillTopLeft);
    if (first == null || !context.mounted) return;
    final second = await waitForPad(context, ref, l.liveMidiFill, l.liveMidiFillBelow);
    if (second == null || !context.mounted) return;
    if (second.trigger == first.trigger || second.kind != first.kind) {
      _say(context, l.liveMidiFillSame);
      return;
    }
    final block = padBlock(ref.read(liveGridProvider), topLeft: first.trigger, below: second.trigger);
    for (final (target, trigger) in block) {
      assignLiveMidi(ref.read, target, trigger);
    }
    _say(context, l.liveMidiFilled(block.length));
  }
}

bool _hasController(BuildContext context, WidgetRef ref) {
  if (ref.read(midiControlProvider).service.connectedDevices.isNotEmpty) return true;
  _say(context, context.l10n.midiCtlNoneConnected);
  return false;
}

void _say(BuildContext context, String text) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(text)));
}

/// Shows "press the pad" until a controller sends a press (returned) or
/// Cancel is tapped (null).
Future<MidiInputMessage?> waitForPad(BuildContext context, WidgetRef ref, String title, String hint) async {
  final service = ref.read(midiControlProvider).service;
  final pending = service.learn();
  var open = true;
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      key: const ValueKey('live-midi-wait'),
      title: Text(title),
      content: Row(
        children: [
          const Icon(Icons.hearing, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(child: Text(hint)),
        ],
      ),
      actions: [TextButton(onPressed: service.cancelLearn, child: Text(context.l10n.commonCancel))],
    ),
  ).then((_) => open = false);
  final message = await pending;
  if (open) navigator.pop();
  return message;
}

/// A tap on [target] while learning: waits for the pad and binds it.
/// False when not learning, so the tap does its usual job.
Future<bool> liveMidiTap(BuildContext context, WidgetRef ref, LiveMidiTarget target, String name) async {
  if (!ref.read(liveMidiLearnProvider)) return false;
  if (!_hasController(context, ref)) return true;
  final l = context.l10n;
  final message = await waitForPad(context, ref, name, l.liveMidiPressPad);
  if (message == null || !context.mounted) return true;
  final mapping = assignLiveMidi(ref.read, target, message.trigger);
  _say(context, l.liveMidiAssigned(shortTriggerLabel(mapping.trigger), name));
  return true;
}

/// A long press on [target] while learning: unbinds its pad. False when not
/// learning (the long press keeps its usual job).
bool liveMidiLongPress(BuildContext context, WidgetRef ref, LiveMidiTarget target) {
  if (!ref.read(liveMidiLearnProvider)) return false;
  if (clearLiveMidi(ref.read, target)) _say(context, context.l10n.liveMidiCleared);
  return true;
}

/// The pad bound to [target], as a small tag; nothing when it has none.
class LiveMidiBadge extends ConsumerWidget {
  final LiveMidiTarget target;
  const LiveMidiBadge(this.target, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapping = ref.watch(midiMappingsProvider.select((all) => liveMidiMappingFor(all, target)));
    if (mapping == null) return const SizedBox.shrink();
    final learning = ref.watch(liveMidiLearnProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: (learning ? AppColors.accent : AppColors.textDim).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        shortTriggerLabel(mapping.trigger),
        style: TextStyle(
          color: learning ? AppColors.accent : AppColors.textDim,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
