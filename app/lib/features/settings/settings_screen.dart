import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/universe_config.dart';
import '../../state/artnet_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _deviceNameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(artNetSettingsProvider);
    _deviceNameController = TextEditingController(text: settings.deviceName);
    _hostController = TextEditingController(text: settings.host);
    _portController = TextEditingController(text: settings.port.toString());
  }

  @override
  void dispose() {
    _deviceNameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _applyFieldsToProvider() {
    ref
        .read(artNetSettingsProvider.notifier)
        .update(
          (current) => current.copyWith(
            deviceName: _deviceNameController.text.trim(),
            host: _hostController.text.trim(),
            port: int.tryParse(_portController.text.trim()) ?? current.port,
          ),
        );
  }

  Future<void> _runTest() async {
    _applyFieldsToProvider();
    setState(() => _testing = true);
    await ref
        .read(connectionStatusProvider.notifier)
        .testConnection(ref.read(artNetSettingsProvider));
    if (mounted) setState(() => _testing = false);
  }

  Future<void> _sendTestPulse() async {
    final universes = ref.read(universesProvider);
    if (universes.isEmpty) return;
    final service = ref.read(artNetServiceProvider);
    final universe = universes.first;
    if (!service.isConnected) {
      await service.connect(ref.read(artNetSettingsProvider));
    }
    service.setChannel(universe, 0, 255);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    service.setChannel(universe, 0, 0);
  }

  Future<void> _editUniverse(UniverseConfig universe) async {
    final nameController = TextEditingController(text: universe.name);
    final netController = TextEditingController(text: universe.net.toString());
    final subController = TextEditingController(text: universe.subNet.toString());
    final uniController = TextEditingController(text: universe.universe.toString());

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Edit Universe'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: netController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Net'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: subController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Sub'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: uniController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Universe'),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (result == true) {
      ref
          .read(universesProvider.notifier)
          .updateUniverse(
            universe.id,
            (current) => current.copyWith(
              name: nameController.text.trim().isEmpty ? current.name : nameController.text.trim(),
              net: int.tryParse(netController.text) ?? current.net,
              subNet: int.tryParse(subController.text) ?? current.subNet,
              universe: int.tryParse(uniController.text) ?? current.universe,
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(artNetSettingsProvider);
    final universes = ref.watch(universesProvider);
    final status = ref.watch(connectionStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _SectionTitle('Art-Net Connection'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _deviceNameController,
                    decoration: const InputDecoration(labelText: 'Device Name'),
                    onChanged: (_) => _applyFieldsToProvider(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _hostController,
                          decoration: const InputDecoration(labelText: 'Host / IP Address'),
                          onChanged: (_) => _applyFieldsToProvider(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _portController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Port'),
                          onChanged: (_) => _applyFieldsToProvider(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('Unicast')),
                            ButtonSegment(value: true, label: Text('Broadcast')),
                          ],
                          selected: {settings.broadcast},
                          onSelectionChanged: (selection) {
                            ref
                                .read(artNetSettingsProvider.notifier)
                                .update((current) => current.copyWith(broadcast: selection.first));
                          },
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: _ConnectionStatusLine(status: status, testing: _testing)),
                      FilledButton(
                        onPressed: _testing ? null : _runTest,
                        child: _testing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Test'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _SectionTitle('Universes', trailing: '${universes.length} active'),
          Card(
            child: Column(
              children: [
                for (final universe in universes)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.panel2,
                      foregroundColor: AppColors.accent2,
                      child: Text('${universes.indexOf(universe) + 1}'),
                    ),
                    title: Text(universe.name),
                    subtitle: Text(
                      'Net ${universe.net} · Sub ${universe.subNet} · Universe ${universe.universe}',
                      style: appMonoStyle(fontSize: 11, color: AppColors.textFaint),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () => _editUniverse(universe),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => ref.read(universesProvider.notifier).addUniverse(),
            icon: const Icon(Icons.add),
            label: const Text('Add Universe'),
          ),
          const SizedBox(height: 20),
          _SectionTitle('About & Diagnostics'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('App Version', style: TextStyle(color: AppColors.textFaint)),
                      Text('1.0.0 (build 1)', style: appMonoStyle()),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _sendTestPulse,
                      icon: const Icon(Icons.bolt_outlined),
                      label: const Text('Send Test DMX Pulse'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;
  final String? trailing;

  const _SectionTitle(this.label, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: AppColors.textFaint,
            ),
          ),
          if (trailing != null)
            Text(trailing!, style: appMonoStyle(fontSize: 11, color: AppColors.textFaint)),
        ],
      ),
    );
  }
}

class _ConnectionStatusLine extends StatelessWidget {
  final ConnectionStatus status;
  final bool testing;

  const _ConnectionStatusLine({required this.status, required this.testing});

  @override
  Widget build(BuildContext context) {
    if (testing) {
      return const Text('Testing…', style: TextStyle(color: AppColors.textFaint));
    }
    if (!status.attempted) {
      return const Text('Not tested yet', style: TextStyle(color: AppColors.textFaint));
    }
    if (status.success) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            'Connected · ${status.latency?.inMilliseconds ?? 0}ms',
            style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600),
          ),
        ],
      );
    }
    return Text(
      status.error ?? 'No reply received',
      style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
      overflow: TextOverflow.ellipsis,
    );
  }
}

