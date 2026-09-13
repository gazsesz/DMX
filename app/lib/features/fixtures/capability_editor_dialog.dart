import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/channel_capability.dart';

/// Edits the labelled value spans of a single channel.
///
/// This is where a channel stops being a bare 0-255 dial: fill in that a
/// strobe channel is "0-3 closed / 4-7 open / 8-215 strobe / 216-255
/// random" and every fader in the app starts naming what it's set to,
/// instead of leaving you to find the right number by trial and error.
///
/// Returns null when cancelled, or the new (normalised) list on save —
/// including an empty list, which means "back to a plain fader".
Future<List<ChannelCapability>?> showCapabilityEditor(
  BuildContext context, {
  required String channelLabel,
  required List<ChannelCapability> initial,
}) {
  return showDialog<List<ChannelCapability>>(
    context: context,
    builder: (context) => _CapabilityEditorDialog(channelLabel: channelLabel, initial: initial),
  );
}

/// One editable row, holding its own controllers so typing doesn't fight
/// with rebuilds.
class _Row {
  final TextEditingController min;
  final TextEditingController max;
  final TextEditingController label;
  CapabilityKind kind;

  _Row(ChannelCapability source)
    : min = TextEditingController(text: '${source.min}'),
      max = TextEditingController(text: '${source.max}'),
      label = TextEditingController(text: source.label),
      kind = source.kind;

  void dispose() {
    min.dispose();
    max.dispose();
    label.dispose();
  }

  ChannelCapability toCapability() => ChannelCapability(
    min: (int.tryParse(min.text.trim()) ?? 0).clamp(0, 255),
    max: (int.tryParse(max.text.trim()) ?? 0).clamp(0, 255),
    label: label.text.trim(),
    kind: kind,
  );
}

/// The shape almost every strobe channel takes. Offered as one tap because
/// it's the range users most often need and least often want to type.
const _strobeTemplate = <ChannelCapability>[
  ChannelCapability(min: 0, max: 3, label: 'Closed', kind: CapabilityKind.off),
  ChannelCapability(min: 4, max: 7, label: 'Open', kind: CapabilityKind.slot),
  ChannelCapability(min: 8, max: 215, label: 'Strobe slow to fast', kind: CapabilityKind.range),
  ChannelCapability(min: 216, max: 255, label: 'Random strobe', kind: CapabilityKind.range),
];

class _CapabilityEditorDialog extends StatefulWidget {
  final String channelLabel;
  final List<ChannelCapability> initial;

  const _CapabilityEditorDialog({required this.channelLabel, required this.initial});

  @override
  State<_CapabilityEditorDialog> createState() => _CapabilityEditorDialogState();
}

class _CapabilityEditorDialogState extends State<_CapabilityEditorDialog> {
  late List<_Row> _rows = [for (final c in widget.initial) _Row(c)];

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _replaceAll(List<ChannelCapability> capabilities) {
    setState(() {
      for (final row in _rows) {
        row.dispose();
      }
      _rows = [for (final c in capabilities) _Row(c)];
    });
  }

  void _add() {
    // Start where the last range left off, so filling a channel in from top
    // to bottom is just "add, type a name, add".
    final lastMax = _rows.isEmpty ? -1 : _rows.map((r) => r.toCapability().max).reduce((a, b) => a > b ? a : b);
    final start = (lastMax + 1).clamp(0, 255);
    setState(() {
      _rows.add(_Row(ChannelCapability(min: start, max: 255, label: '')));
    });
  }

  Future<void> _splitEvenly() async {
    final controller = TextEditingController(text: '8');
    final count = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Split into equal slots'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'How many slots?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('Split'),
          ),
        ],
      ),
    );
    if (count == null || count < 1 || count > 64) return;
    final step = 256 / count;
    _replaceAll([
      for (var i = 0; i < count; i++)
        ChannelCapability(
          min: (i * step).floor(),
          max: ((i + 1) * step).floor() - 1,
          label: 'Slot ${i + 1}',
        ),
    ]);
  }

  Widget _rowTile(int index) {
    final row = _rows[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            child: TextField(
              controller: row.min,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: appMonoStyle(fontSize: 12),
              decoration: const InputDecoration(isDense: true, labelText: 'From'),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 48,
            child: TextField(
              controller: row.max,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: appMonoStyle(fontSize: 12),
              decoration: const InputDecoration(isDense: true, labelText: 'To'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: row.label,
              style: const TextStyle(fontSize: 12.5),
              decoration: const InputDecoration(isDense: true, labelText: 'Name'),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 74,
            child: DropdownButtonFormField<CapabilityKind>(
              initialValue: row.kind,
              isExpanded: true,
              style: const TextStyle(fontSize: 11.5, color: AppColors.text),
              decoration: const InputDecoration(isDense: true),
              items: [
                for (final kind in CapabilityKind.values)
                  DropdownMenuItem(value: kind, child: Text(kind.label)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => row.kind = value);
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 17, color: AppColors.textFaint),
            onPressed: () => setState(() => _rows.removeAt(index)..dispose()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.panel,
      title: Text('${widget.channelLabel} — value ranges'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Name what each part of this channel\'s 0-255 span does. '
              'Use "Range" for a continuous span you fine-tune (strobe speed, '
              'fade speed), "Slot" for a fixed choice (a gobo, a colour), and '
              '"Off" for the inactive end.',
              style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    if (_rows.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          'No ranges — this channel stays a plain 0-255 fader.',
                          style: TextStyle(fontSize: 12, color: AppColors.textFaint),
                        ),
                      )
                    else
                      for (var i = 0; i < _rows.length; i++) _rowTile(i),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                TextButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add range'),
                ),
                TextButton.icon(
                  onPressed: () => _replaceAll(_strobeTemplate),
                  icon: const Icon(Icons.flash_on, size: 16),
                  label: const Text('Strobe template'),
                ),
                TextButton.icon(
                  onPressed: _splitEvenly,
                  icon: const Icon(Icons.grid_on, size: 16),
                  label: const Text('Split evenly…'),
                ),
                if (_rows.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _replaceAll(const []),
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Clear'),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            normalizeCapabilities([for (final row in _rows) row.toCapability()]),
          ),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
