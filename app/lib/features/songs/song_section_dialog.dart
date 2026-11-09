import 'package:flutter/material.dart';

import '../../models/song_show.dart';
import 'song_timeline.dart';
import '../../l10n/l10n.dart';

/// What the section dialog returns: an edited section, or a delete request.
class SectionDialogResult {
  final SongSection? section;
  final bool delete;

  const SectionDialogResult.save(SongSection this.section) : delete = false;
  const SectionDialogResult.remove() : section = null, delete = true;
}

/// Edits one section: its kind and name, length in bars, and whether its
/// cues play at all.
Future<SectionDialogResult?> showSectionDialog(
  BuildContext context, {
  required SongSection section,
  bool isNew = false,
}) {
  return showDialog<SectionDialogResult>(
    context: context,
    builder: (context) => _SectionDialog(initial: section, isNew: isNew),
  );
}

class _SectionDialog extends StatefulWidget {
  const _SectionDialog({required this.initial, required this.isNew});
  final SongSection initial;
  final bool isNew;

  @override
  State<_SectionDialog> createState() => _SectionDialogState();
}

class _SectionDialogState extends State<_SectionDialog> {
  late SongSectionKind _kind = widget.initial.kind;
  late double _bars = (widget.initial.lengthBeats / 4).clamp(1, 256);
  late bool _enabled = widget.initial.enabled;
  late final _label = TextEditingController(text: widget.initial.label);

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  SongSection get _result => SongSection(
    startBeat: widget.initial.startBeat,
    lengthBeats: _bars * 4,
    kind: _kind,
    label: _label.text.trim(),
    enabled: _enabled,
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.isNew ? context.l10n.songNewSection : context.l10n.songSection),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            children: [
              for (final k in SongSectionKind.values)
                ChoiceChip(
                  key: ValueKey('section-kind-${k.name}'),
                  label: Text(sectionKindLabel(k, context.l10n)),
                  selected: k == _kind,
                  onSelected: (_) => setState(() => _kind = k),
                ),
            ],
          ),
          TextField(
            controller: _label,
            decoration: InputDecoration(labelText: context.l10n.songNameOptional),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(context.l10n.songLength),
              IconButton(
                key: const ValueKey('section-shorter'),
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _bars > 1 ? () => setState(() => _bars -= _bars > 8 ? 4 : 1) : null,
              ),
              Text(context.l10n.songBars(_bars.round())),
              IconButton(
                key: const ValueKey('section-longer'),
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => setState(() => _bars += _bars >= 8 ? 4 : 1),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.songPlayItsCues),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
        ],
      ),
    ),
    actions: [
      if (!widget.isNew)
        TextButton(
          key: const ValueKey('section-delete'),
          onPressed: () => Navigator.pop(context, const SectionDialogResult.remove()),
          child: Text(context.l10n.scDelete),
        ),
      TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.commonCancel)),
      FilledButton(
        key: const ValueKey('section-save'),
        onPressed: () => Navigator.pop(context, SectionDialogResult.save(_result)),
        child: Text(context.l10n.commonSave),
      ),
    ],
  );
}
