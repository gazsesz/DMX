import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/channel_function.dart';
import '../../models/fixture_profile.dart';
import '../../state/fixture_providers.dart';
import 'capability_editor_dialog.dart';
import '../../l10n/l10n.dart';

class FixtureEditorScreen extends ConsumerStatefulWidget {
  final FixtureProfile? existing;

  const FixtureEditorScreen({super.key, this.existing});

  @override
  ConsumerState<FixtureEditorScreen> createState() => _FixtureEditorScreenState();
}

class _FixtureEditorScreenState extends ConsumerState<FixtureEditorScreen> {
  late final TextEditingController _nameController;
  late FixtureCategory _category;
  late List<FixtureChannelDraft> _channels;
  late final TextEditingController _panRangeController;
  late final TextEditingController _tiltRangeController;

  bool get _isEditing => widget.existing != null;

  bool _defaultNameSet = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _category = existing?.category ?? FixtureCategory.generic;
    _panRangeController = TextEditingController(
      text: '${existing?.panRangeDeg ?? FixtureProfile.defaultPanRangeDeg}',
    );
    _tiltRangeController = TextEditingController(
      text: '${existing?.tiltRangeDeg ?? FixtureProfile.defaultTiltRangeDeg}',
    );
    _channels = existing == null
        ? [FixtureChannelDraft(function: ChannelFunction.dimmer)]
        : [
            for (final channel in existing.channels)
              FixtureChannelDraft(
                function: channel.function,
                customLabel: channel.customLabel,
                capabilities: channel.capabilities,
              ),
          ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The default name is localised, which can't be read in initState.
    if (widget.existing == null && !_defaultNameSet) {
      _defaultNameSet = true;
      _nameController.text = context.l10n.scNewFixture;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _panRangeController.dispose();
    _tiltRangeController.dispose();
    super.dispose();
  }

  void _addChannel() {
    setState(() => _channels.add(FixtureChannelDraft(function: ChannelFunction.generic)));
  }

  void _removeChannel(int index) {
    setState(() => _channels.removeAt(index));
  }

  Future<void> _editCapabilities(int index) async {
    final draft = _channels[index];
    final updated = await showCapabilityEditor(
      context,
      channelLabel: draft.customLabel ?? draft.function.label,
      initial: draft.capabilities,
      function: draft.function,
    );
    if (updated == null) return;
    setState(() => draft.capabilities = updated);
  }

  bool get _hasPanTilt => _channels.any((c) => c.function.isPanTilt);

  int _rangeFrom(TextEditingController controller, int fallback) {
    final value = int.tryParse(controller.text.trim());
    return value == null || value <= 0 ? fallback : value.clamp(1, 720);
  }

  void _save() {
    if (_channels.isEmpty || _nameController.text.trim().isEmpty) return;
    final library = ref.read(fixtureLibraryProvider.notifier);
    final panRange = _rangeFrom(_panRangeController, FixtureProfile.defaultPanRangeDeg);
    final tiltRange = _rangeFrom(_tiltRangeController, FixtureProfile.defaultTiltRangeDeg);
    final FixtureProfile profile;
    if (_isEditing) {
      profile = library.updateCustom(
        widget.existing!.id,
        name: _nameController.text.trim(),
        category: _category,
        channels: _channels,
        panRangeDeg: panRange,
        tiltRangeDeg: tiltRange,
      );
      ref.read(patchedFixturesProvider.notifier).refreshProfile(profile);
    } else {
      profile = library.addCustom(
        name: _nameController.text.trim(),
        category: _category,
        channels: _channels,
        panRangeDeg: panRange,
        tiltRangeDeg: tiltRange,
      );
    }
    Navigator.of(context).pop(profile);
  }

  Future<bool> _confirmDiscard() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text(_isEditing ? context.l10n.scDiscardChanges : context.l10n.scDiscardFixture),
        content: Text(_isEditing ? context.l10n.scYourEditsHaveNot : context.l10n.scThisFixtureHasNot),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.scKeepEditing)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.scDiscard),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? context.l10n.scEditFixture : context.l10n.scNewFixture),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _save, tooltip: context.l10n.commonSave),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(labelText: context.l10n.scFixtureName),
          ),
          SizedBox(height: 16),
          Text(
            context.l10n.scFixtureType,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
          ),
          SizedBox(height: 8),
          SegmentedButton<FixtureCategory>(
            segments: [
              ButtonSegment(value: FixtureCategory.movingHead, label: Text(context.l10n.scMovingHead)),
              ButtonSegment(value: FixtureCategory.rgb, label: Text(context.l10n.scRgbPar)),
              ButtonSegment(value: FixtureCategory.generic, label: Text(context.l10n.scGeneric)),
            ],
            selected: {_category},
            onSelectionChanged: (s) => setState(() => _category = s.first),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.l10n.scChannelMap,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
              ),
              Text(
                context.l10n.scChannels(_channels.length),
                style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
              ),
            ],
          ),
          if (_isEditing)
            Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                context.l10n.scChangingTheChannelCount,
                style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
              ),
            ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < _channels.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 13,
                          backgroundColor: AppColors.panel2,
                          foregroundColor: AppColors.accent2,
                          child: Text('${i + 1}', style: const TextStyle(fontSize: 11)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<ChannelFunction>(
                            initialValue: _channels[i].function,
                            isExpanded: true,
                            decoration: const InputDecoration(isDense: true),
                            items: [
                              for (final fn in ChannelFunction.values)
                                DropdownMenuItem(value: fn, child: Text(fn.label)),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _channels[i].function = value);
                              }
                            },
                          ),
                        ),
                        // Ranges are per channel and most channels have
                        // none, so they live behind a button that shows
                        // the count rather than taking room in every row.
                        TextButton(
                          onPressed: () => _editCapabilities(i),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(52, 34),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            foregroundColor: _channels[i].capabilities.isEmpty
                                ? AppColors.textFaint
                                : AppColors.accent2,
                          ),
                          child: Text(
                            _channels[i].capabilities.isEmpty
                                ? context.l10n.scRanges
                                : context.l10n.scRanges2(_channels[i].capabilities.length),
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18, color: AppColors.textFaint),
                          onPressed: () => _removeChannel(i),
                        ),
                      ],
                    ),
                  ),
                ListTile(
                  dense: true,
                  onTap: _addChannel,
                  leading: const Icon(Icons.add, size: 18, color: AppColors.accent),
                  title: Text(context.l10n.scAddChannel, style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          if (_hasPanTilt) ...[
            const SizedBox(height: 20),
            Text(
              context.l10n.scMovementRange,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
            ),
            Text(
              context.l10n.scHowFarTheHead,
              style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _panRangeController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: context.l10n.scPanRange, suffixText: '°'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _tiltRangeController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: context.l10n.scTiltRange, suffixText: '°'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(_isEditing ? context.l10n.scSaveChanges : context.l10n.scSaveFixture),
          )),
        ],
      ),
      ),
    );
  }
}
