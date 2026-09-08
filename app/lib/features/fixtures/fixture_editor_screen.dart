import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../models/channel_function.dart';
import '../../models/fixture_profile.dart';
import '../../state/fixture_providers.dart';

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

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? 'New Fixture');
    _category = existing?.category ?? FixtureCategory.generic;
    _channels = existing == null
        ? [FixtureChannelDraft(function: ChannelFunction.dimmer)]
        : [
            for (final channel in existing.channels)
              FixtureChannelDraft(function: channel.function, customLabel: channel.customLabel),
          ];
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _addChannel() {
    setState(() => _channels.add(FixtureChannelDraft(function: ChannelFunction.generic)));
  }

  void _removeChannel(int index) {
    setState(() => _channels.removeAt(index));
  }

  void _save() {
    if (_channels.isEmpty || _nameController.text.trim().isEmpty) return;
    final library = ref.read(fixtureLibraryProvider.notifier);
    final FixtureProfile profile;
    if (_isEditing) {
      profile = library.updateCustom(
        widget.existing!.id,
        name: _nameController.text.trim(),
        category: _category,
        channels: _channels,
      );
      ref.read(patchedFixturesProvider.notifier).refreshProfile(profile);
    } else {
      profile = library.addCustom(
        name: _nameController.text.trim(),
        category: _category,
        channels: _channels,
      );
    }
    Navigator.of(context).pop(profile);
  }

  Future<bool> _confirmDiscard() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text(_isEditing ? 'Discard changes?' : 'Discard fixture?'),
        content: Text(_isEditing ? 'Your edits have not been saved.' : 'This fixture has not been saved yet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep Editing')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
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
        title: Text(_isEditing ? 'Edit Fixture' : 'New Fixture'),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _save, tooltip: 'Save'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Fixture Name'),
          ),
          const SizedBox(height: 16),
          const Text(
            'FIXTURE TYPE',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
          ),
          const SizedBox(height: 8),
          SegmentedButton<FixtureCategory>(
            segments: const [
              ButtonSegment(value: FixtureCategory.movingHead, label: Text('Moving Head')),
              ButtonSegment(value: FixtureCategory.rgb, label: Text('RGB / Par')),
              ButtonSegment(value: FixtureCategory.generic, label: Text('Generic')),
            ],
            selected: {_category},
            onSelectionChanged: (s) => setState(() => _category = s.first),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'CHANNEL MAP',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textFaint),
              ),
              Text(
                '${_channels.length} channels',
                style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
              ),
            ],
          ),
          if (_isEditing)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Changing the channel count/order updates every patched instance of this fixture — existing scenes may need re-checking.',
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
                  title: const Text('Add Channel', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(_isEditing ? 'Save Changes' : 'Save Fixture'),
          )),
        ],
      ),
      ),
    );
  }
}
