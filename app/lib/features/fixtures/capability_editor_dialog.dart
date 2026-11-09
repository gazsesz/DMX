import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wheel_looks.dart';
import '../../models/channel_capability.dart';
import '../../models/channel_function.dart';
import '../../l10n/l10n.dart';

/// Edits the labelled value spans of a single channel.
///
/// This is where a channel stops being a bare 0-255 dial: fill in that a
/// strobe channel is "0-3 closed / 4-7 open / 8-215 strobe / 216-255
/// random" and every fader in the app starts naming what it's set to,
/// instead of leaving you to find the right number by trial and error.
///
/// Returns null when cancelled, or the new (normalised) list on save —
/// including an empty list, which means "back to a plain fader".
///
/// [function] says what the channel is, so a colour wheel's rows can be
/// given a swatch colour and a gobo wheel's a picture.
Future<List<ChannelCapability>?> showCapabilityEditor(
  BuildContext context, {
  required String channelLabel,
  required List<ChannelCapability> initial,
  ChannelFunction? function,
}) {
  return showDialog<List<ChannelCapability>>(
    context: context,
    builder: (context) => _CapabilityEditorDialog(channelLabel: channelLabel, initial: initial, function: function),
  );
}

/// One editable row, holding its own controllers so typing doesn't fight
/// with rebuilds.
class _Row {
  final TextEditingController min;
  final TextEditingController max;
  final TextEditingController label;
  CapabilityKind kind;
  String? colorHex;
  String? glyph;

  _Row(ChannelCapability source)
    : min = TextEditingController(text: '${source.min}'),
      max = TextEditingController(text: '${source.max}'),
      label = TextEditingController(text: source.label),
      kind = source.kind,
      colorHex = source.colorHex,
      glyph = source.glyph;

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
    colorHex: colorHex,
    glyph: glyph,
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
  final ChannelFunction? function;

  const _CapabilityEditorDialog({required this.channelLabel, required this.initial, this.function});

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
        title: Text(context.l10n.scSplitIntoEqualSlots),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: context.l10n.scHowManySlots),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.commonCancel)),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: Text(context.l10n.scSplit),
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
          label: context.l10n.scSlot(i + 1),
        ),
    ]);
  }

  /// The swatch a colour-wheel slot shows in the Scene editor. Unset means
  /// "guess from the name", which is what the button then previews.
  Widget _colorButton(_Row row) {
    final preview = row.toCapability();
    return PopupMenuButton<String>(
      tooltip: context.l10n.scSwatchColour,
      color: AppColors.panel2,
      onSelected: (hex) => setState(() => row.colorHex = hex.isEmpty ? null : hex),
      itemBuilder: (context) => [
        PopupMenuItem(value: '', child: Text(context.l10n.scGuessFromTheName)),
        for (final entry in wheelColorChoices.entries)
          PopupMenuItem(
            value: entry.value,
            child: Row(
              children: [
                WheelSwatch(colors: wheelColorsFor(ChannelCapability(min: 0, max: 0, label: '', colorHex: entry.value)), size: 20),
                const SizedBox(width: 10),
                Text(entry.key),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: WheelSwatch(colors: wheelColorsFor(preview), fallbackText: '?', size: 26),
      ),
    );
  }

  /// The picture a gobo slot shows in the Scene editor.
  Widget _glyphButton(_Row row) {
    final preview = row.toCapability();
    return PopupMenuButton<String>(
      tooltip: context.l10n.scGoboPicture,
      color: AppColors.panel2,
      onSelected: (name) => setState(() => row.glyph = name.isEmpty ? null : name),
      itemBuilder: (context) => [
        PopupMenuItem(value: '', child: Text(context.l10n.scGuessFromTheName)),
        for (final name in goboGlyphNames)
          PopupMenuItem(
            value: name,
            child: Row(
              children: [
                GoboGlyph(glyph: name, size: 24),
                const SizedBox(width: 10),
                Text(name[0].toUpperCase() + name.substring(1)),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: GoboGlyph(glyph: goboGlyphFor(preview), fallbackText: '?', size: 28),
      ),
    );
  }

  Widget _rowTile(int index) {
    final row = _rows[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 64,
            child: TextField(
              controller: row.min,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: appMonoStyle(fontSize: 12),
              decoration: InputDecoration(isDense: true, labelText: context.l10n.scFrom),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 64,
            child: TextField(
              controller: row.max,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: appMonoStyle(fontSize: 12),
              decoration: InputDecoration(isDense: true, labelText: context.l10n.scTo),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: row.label,
              style: const TextStyle(fontSize: 12.5),
              decoration: InputDecoration(isDense: true, labelText: context.l10n.commonName),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 92,
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
          if (widget.function == ChannelFunction.colorWheel) _colorButton(row),
          if (widget.function == ChannelFunction.gobo) _glyphButton(row),
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
      title: Text(context.l10n.scValueRanges(widget.channelLabel)),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.scNameWhatEachPart,
              style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    if (_rows.isEmpty)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          context.l10n.scNoRangesThisChannel,
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
                  label: Text(context.l10n.scAddRange),
                ),
                TextButton.icon(
                  onPressed: () => _replaceAll(_strobeTemplate),
                  icon: const Icon(Icons.flash_on, size: 16),
                  label: Text(context.l10n.scStrobeTemplate),
                ),
                TextButton.icon(
                  onPressed: _splitEvenly,
                  icon: const Icon(Icons.grid_on, size: 16),
                  label: Text(context.l10n.scSplitEvenly),
                ),
                if (_rows.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _replaceAll(const []),
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: Text(context.l10n.scClear),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.commonCancel)),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            normalizeCapabilities([for (final row in _rows) row.toCapability()]),
          ),
          child: Text(context.l10n.commonDone),
        ),
      ],
    );
  }
}
