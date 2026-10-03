import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/wheel_looks.dart';
import '../../../models/channel_capability.dart';

/// The fixed choices on a wheel (each colour, each gobo) as opposed to the
/// continuous effects that share the channel (wheel spin, gobo shake).
bool _isFixedSlot(ChannelCapability c) => c.kind != CapabilityKind.range;

/// A colour wheel as swatches: one per slot, half colours split in two, and
/// the spin/rainbow ranges as chips underneath.
class ColorWheelPicker extends StatelessWidget {
  final List<ChannelCapability> capabilities;
  final int value;
  final ValueChanged<int> onChanged;

  const ColorWheelPicker({super.key, required this.capabilities, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final slots = capabilities.where(_isFixedSlot).toList();
    final effects = capabilities.where((c) => !_isFixedSlot(c)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < slots.length; i++)
              Tooltip(
                message: '${slots[i].label} · ${slots[i].rangeLabel}',
                child: InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => onChanged(slots[i].pickValue),
                  child: WheelSwatch(
                    colors: wheelColorsFor(slots[i]),
                    fallbackText: _slotNumber(slots[i], i),
                    selected: slots[i].contains(value),
                  ),
                ),
              ),
          ],
        ),
        if (effects.isNotEmpty) ...[
          const SizedBox(height: 10),
          SlotChips(capabilities: effects, value: value, onChanged: onChanged),
        ],
        const SizedBox(height: 6),
        Text(_nameOf(capabilities, value), style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint)),
      ],
    );
  }
}

/// A gobo wheel as pictures, with shake/scroll ranges as chips.
class GoboPicker extends StatelessWidget {
  final List<ChannelCapability> capabilities;
  final int value;
  final ValueChanged<int> onChanged;

  const GoboPicker({super.key, required this.capabilities, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final slots = capabilities.where(_isFixedSlot).toList();
    final effects = capabilities.where((c) => !_isFixedSlot(c)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 10,
          children: [
            for (var i = 0; i < slots.length; i++)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onChanged(slots[i].pickValue),
                child: SizedBox(
                  width: 64,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GoboGlyph(
                        glyph: goboGlyphFor(slots[i]),
                        fallbackText: _slotNumber(slots[i], i),
                        size: 46,
                        selected: slots[i].contains(value),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        slots[i].label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5,
                          height: 1.15,
                          fontWeight: slots[i].contains(value) ? FontWeight.w800 : FontWeight.w500,
                          color: slots[i].contains(value) ? AppColors.accent : AppColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (effects.isNotEmpty) ...[
          const SizedBox(height: 10),
          SlotChips(capabilities: effects, value: value, onChanged: onChanged),
        ],
      ],
    );
  }
}

/// A channel's named ranges as one row of chips — the prism in/out choices,
/// or a wheel's spin and shake effects.
class SlotChips extends StatelessWidget {
  final List<ChannelCapability> capabilities;
  final int value;
  final ValueChanged<int> onChanged;

  const SlotChips({super.key, required this.capabilities, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final capability in capabilities)
          ChoiceChip(
            label: Text(capability.label, style: const TextStyle(fontSize: 11)),
            selected: capability.contains(value),
            tooltip: capability.rangeLabel,
            onSelected: (_) => onChanged(capability.pickValue),
          ),
      ],
    );
  }
}

String _nameOf(List<ChannelCapability> capabilities, int value) {
  for (final c in capabilities) {
    if (c.contains(value)) return '${c.label} · $value';
  }
  return '$value';
}

/// The number to print on a slot with no picture: the one in its name
/// ("Gobo 7" → 7) when there is one, else its place on the wheel.
String _slotNumber(ChannelCapability slot, int index) =>
    RegExp(r'\d+').firstMatch(slot.label)?.group(0) ?? '${index + 1}';
