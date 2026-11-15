import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/midi/midi_input_message.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/l10n.dart';
import '../../l10n/status_messages.dart';
import '../../models/midi_mapping.dart';
import '../../state/bank_providers.dart';
import '../../state/chase_providers.dart';
import '../../state/color_override_providers.dart';
import '../../state/midi_control_providers.dart';
import '../../state/provider_reader.dart';
import '../../state/smart_program_providers.dart';

/// Setup → MIDI controllers: connect USB / Bluetooth controllers, and bind
/// their pads, buttons and faders to the app's functions with MIDI learn.
class MidiControlScreen extends ConsumerStatefulWidget {
  const MidiControlScreen({super.key});

  @override
  ConsumerState<MidiControlScreen> createState() => _MidiControlScreenState();
}

class _MidiControlScreenState extends ConsumerState<MidiControlScreen> {
  List<MidiDevice> _devices = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final devices = await ref.read(midiControlProvider).service.devices();
    if (mounted) setState(() { _devices = devices; _loading = false; });
  }

  Future<void> _scanBluetooth() async {
    final service = ref.read(midiControlProvider).service;
    // Refresh the list as the scan finds things.
    final ticker = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    final error = await service.scanBluetooth();
    ticker.cancel();
    await _refresh();
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(localizeStatus(error, context.l10n))));
    }
  }

  Future<void> _toggle(MidiDevice device) async {
    final service = ref.read(midiControlProvider).service;
    if (service.isConnected(device)) {
      service.disconnect(device);
    } else {
      final ok = await service.connect(device);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.midiCtlConnectFailed(device.name))),
        );
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _edit([MidiMapping? existing]) async {
    final result = await showDialog<MidiMapping>(
      context: context,
      builder: (_) => _MappingEditor(existing: existing),
    );
    if (result != null) ref.read(midiMappingsProvider.notifier).save(result);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final controller = ref.watch(midiControlProvider);
    final service = controller.service;
    final mappings = ref.watch(midiMappingsProvider);
    // Keeps device names/targets fresh when banks are renamed.
    ref.watch(banksProvider);
    ref.watch(chasesProvider);
    ref.watch(smartProgramsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.midiCtlTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: Text(l.midiCtlAddMapping),
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: service.revision,
        builder: (context, _, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            Text(l.midiCtlIntro, style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
            const SizedBox(height: 16),
            _Header(
              l.midiCtlDevices,
              trailing: [
                if (service.bluetoothAvailable)
                  service.isScanning
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 8),
                              Text(l.midiCtlScanning, style: const TextStyle(fontSize: 11)),
                            ],
                          ),
                        )
                      : TextButton.icon(
                          onPressed: _scanBluetooth,
                          icon: const Icon(Icons.bluetooth_searching, size: 18),
                          label: Text(l.midiCtlScanBluetooth),
                        ),
                _loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        icon: const Icon(Icons.refresh, size: 18),
                        tooltip: l.settingsRescan,
                        onPressed: _refresh,
                      ),
              ],
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_devices.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          service.bluetoothAvailable ? l.midiCtlNoDevicesBle : l.midiCtlNoDevices,
                          style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
                        ),
                      )
                    else
                      for (final device in _devices) _deviceTile(device, service.isConnected(device)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            _Monitor(controller: controller),
            const SizedBox(height: 20),
            _Header(l.midiCtlMappings(mappings.length)),
            if (mappings.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(l.midiCtlNoMappings, style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
                ),
              )
            else
              Card(
                child: ValueListenableBuilder<String?>(
                  valueListenable: controller.lastFiredId,
                  builder: (context, firedId, _) => Column(
                    children: [
                      for (final mapping in mappings)
                        _MappingRow(
                          mapping: mapping,
                          fired: mapping.id == firedId,
                          onTap: () => _edit(mapping),
                          onDelete: () => ref.read(midiMappingsProvider.notifier).remove(mapping.id),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _deviceTile(MidiDevice device, bool connected) {
    final l = context.l10n;
    final ble = device.type == MidiDeviceType.ble;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(ble ? Icons.bluetooth : Icons.usb, color: connected ? AppColors.success : AppColors.textDim),
      title: Text(device.name),
      subtitle: Text(
        connected ? l.midiCtlConnected : (ble ? 'Bluetooth' : 'USB'),
        style: TextStyle(fontSize: 11, color: connected ? AppColors.success : AppColors.textFaint),
      ),
      trailing: connected
          ? OutlinedButton(onPressed: () => _toggle(device), child: Text(l.midiCtlDisconnect))
          : FilledButton(onPressed: () => _toggle(device), child: Text(l.midiCtlConnect)),
    );
  }
}

class _Header extends StatelessWidget {
  final String label;
  final List<Widget> trailing;

  const _Header(this.label, {this.trailing = const []});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 0, 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: AppColors.textDim,
            ),
          ),
        ),
        ...trailing,
      ],
    ),
  );
}

/// What the controllers are sending right now, and what the last mapped
/// control did — so "nothing happens" can be told apart from "the pad
/// sends something else than what was learned".
class _Monitor extends StatelessWidget {
  final MidiControlController controller;

  const _Monitor({required this.controller});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.panel2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<MidiInputMessage?>(
            valueListenable: controller.service.lastMessage,
            builder: (context, message, _) => Row(
              children: [
                Icon(Icons.sensors, size: 16, color: message == null ? AppColors.textFaint : AppColors.accent2),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message == null ? l.midiCtlMonitorIdle : l.midiCtlMonitorLast(message.toString()),
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ),
          ValueListenableBuilder<String?>(
            valueListenable: controller.lastResult,
            builder: (context, result, _) => result == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 4, left: 24),
                    child: Text(
                      localizeStatus(result, l),
                      style: const TextStyle(fontSize: 11, color: AppColors.textDim),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MappingRow extends ConsumerWidget {
  final MidiMapping mapping;
  final bool fired;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _MappingRow({required this.mapping, required this.fired, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      color: fired ? AppColors.accent.withValues(alpha: 0.12) : Colors.transparent,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          mapping.action.isContinuous ? Icons.tune : Icons.touch_app_outlined,
          color: fired ? AppColors.accent : AppColors.textDim,
        ),
        title: Text(describeMidiAction(l, ref.read, mapping)),
        subtitle: Text(mapping.trigger.label, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 18),
          tooltip: l.midiCtlDelete,
          onPressed: onDelete,
        ),
      ),
    );
  }
}

/// "Play/stop: Front wash", "Grand master", "Colour: Blue"…
String describeMidiAction(AppLocalizations l, ReadProvider read, MidiMapping mapping) {
  final base = midiActionLabel(l, mapping.action);
  switch (mapping.action) {
    case MidiActionKind.playTarget:
      return '$base: ${midiTargetName(read, mapping) ?? l.midiCtlTargetMissing}';
    case MidiActionKind.color:
      final param = mapping.param;
      if (param == null || param == 'off') return '$base: ${l.midiCtlSceneColours}';
      final color = liveColorNamed(param);
      return '$base: ${color?.label ?? param}';
    default:
      return base;
  }
}

String midiActionLabel(AppLocalizations l, MidiActionKind kind) => switch (kind) {
  MidiActionKind.playTarget => l.midiActPlay,
  MidiActionKind.resume => l.midiActResume,
  MidiActionKind.stop => l.midiActStop,
  MidiActionKind.blackout => l.midiActBlackout,
  MidiActionKind.beatSync => l.midiActBeatSync,
  MidiActionKind.predict => l.midiActPredict,
  MidiActionKind.autoFade => l.midiActAutoFade,
  MidiActionKind.dropout => l.midiActDropout,
  MidiActionKind.tapTempo => l.midiActTapTempo,
  MidiActionKind.color => l.midiActColor,
  MidiActionKind.grandMaster => l.midiActGrandMaster,
  MidiActionKind.stepSpeed => l.midiActStepSpeed,
  MidiActionKind.fadeTime => l.midiActFadeTime,
  MidiActionKind.movementSize => l.midiActMovementSize,
  MidiActionKind.movementSpeed => l.midiActMovementSpeed,
  MidiActionKind.movementShift => l.midiActMovementShift,
  MidiActionKind.movementSmooth => l.midiActMovementSmooth,
  MidiActionKind.movementReset => l.midiActMovementReset,
};

/// One playable thing a pad can start.
class _Target {
  final MidiTargetKind kind;
  final String id;
  final String name;

  const _Target(this.kind, this.id, this.name);
}

/// Add / edit one mapping: pick what it does, then learn the control.
class _MappingEditor extends ConsumerStatefulWidget {
  final MidiMapping? existing;

  const _MappingEditor({this.existing});

  @override
  ConsumerState<_MappingEditor> createState() => _MappingEditorState();
}

class _MappingEditorState extends ConsumerState<_MappingEditor> {
  late MidiActionKind _action = widget.existing?.action ?? MidiActionKind.playTarget;
  late MidiTrigger? _trigger = widget.existing?.trigger;
  late MidiTargetKind? _targetKind = widget.existing?.targetKind;
  late String? _targetId = widget.existing?.targetId;
  late String? _param = widget.existing?.param;
  bool _learning = false;

  @override
  void initState() {
    super.initState();
    // A brand-new mapping starts listening straight away: press the pad,
    // then pick what it does.
    if (widget.existing == null) WidgetsBinding.instance.addPostFrameCallback((_) => _learn());
  }

  @override
  void dispose() {
    if (_learning) ref.read(midiControlProvider).service.cancelLearn();
    super.dispose();
  }

  Future<void> _learn() async {
    final service = ref.read(midiControlProvider).service;
    setState(() => _learning = true);
    final message = await service.learn();
    if (!mounted) return;
    setState(() {
      _learning = false;
      if (message != null) _trigger = message.trigger;
    });
  }

  void _cancelLearn() {
    ref.read(midiControlProvider).service.cancelLearn();
    setState(() => _learning = false);
  }

  List<_Target> _targets() => [
    for (final p in ref.read(smartProgramsProvider)) _Target(MidiTargetKind.smart, p.id, p.name),
    for (final b in ref.read(banksProvider)) _Target(MidiTargetKind.bank, b.id, b.name),
    for (final c in ref.read(chasesProvider)) _Target(MidiTargetKind.chase, c.id, c.name),
  ];

  bool get _complete {
    if (_trigger == null) return false;
    if (_action == MidiActionKind.playTarget) return _targetId != null;
    return true;
  }

  void _save() {
    final trigger = _trigger;
    if (trigger == null) return;
    final play = _action == MidiActionKind.playTarget;
    Navigator.pop(
      context,
      MidiMapping(
        id: widget.existing?.id ?? '',
        trigger: trigger,
        action: _action,
        targetKind: play ? _targetKind : null,
        targetId: play ? _targetId : null,
        param: _action == MidiActionKind.color ? (_param ?? 'off') : null,
      ),
    );
  }

  String _targetKindLabel(MidiTargetKind kind) => switch (kind) {
    MidiTargetKind.bank => context.l10n.midiCtlKindBank,
    MidiTargetKind.chase => context.l10n.midiCtlKindChase,
    MidiTargetKind.smart => context.l10n.midiCtlKindSmart,
  };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final trigger = _trigger;
    final clash = trigger == null
        ? null
        : ref.read(midiMappingsProvider.notifier).boundTo(trigger, exceptId: widget.existing?.id);
    final targets = _targets();

    return AlertDialog(
      title: Text(widget.existing == null ? l.midiCtlNewMapping : l.midiCtlEditMapping),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.midiCtlControl, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _learning ? AppColors.accent.withValues(alpha: 0.12) : AppColors.panel2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _learning ? AppColors.accent : AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(_learning ? Icons.hearing : Icons.piano, size: 18, color: _learning ? AppColors.accent : null),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _learning
                            ? (_action.isContinuous ? l.midiCtlLearnWaitingFader : l.midiCtlLearnWaiting)
                            : (trigger?.label ?? l.midiCtlNotLearned),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontFamily: _learning || trigger == null ? null : 'monospace',
                        ),
                      ),
                    ),
                    _learning
                        ? TextButton(onPressed: _cancelLearn, child: Text(l.commonCancel))
                        : FilledButton.tonal(onPressed: _learn, child: Text(l.midiCtlLearn)),
                  ],
                ),
              ),
              if (clash != null) ...[
                const SizedBox(height: 6),
                Text(
                  l.midiCtlReplaces(describeMidiAction(l, ref.read, clash)),
                  style: const TextStyle(fontSize: 11, color: AppColors.accent),
                ),
              ],
              if (ref.read(midiControlProvider).service.connectedDevices.isEmpty) ...[
                const SizedBox(height: 6),
                Text(l.midiCtlNoneConnected, style: const TextStyle(fontSize: 11, color: AppColors.danger)),
              ],
              const SizedBox(height: 16),
              Text(l.midiCtlAction, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              DropdownButtonFormField<MidiActionKind>(
                initialValue: _action,
                isExpanded: true,
                items: [
                  for (final kind in MidiActionKind.values)
                    DropdownMenuItem(
                      value: kind,
                      child: Row(
                        children: [
                          Icon(kind.isContinuous ? Icons.tune : Icons.touch_app_outlined, size: 16),
                          const SizedBox(width: 8),
                          Flexible(child: Text(midiActionLabel(l, kind), overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                ],
                onChanged: (kind) {
                  if (kind != null) setState(() => _action = kind);
                },
              ),
              const SizedBox(height: 4),
              Text(
                _action.isContinuous ? l.midiCtlContinuousHint : l.midiCtlButtonHint,
                style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint),
              ),
              if (_action == MidiActionKind.playTarget) ...[
                const SizedBox(height: 14),
                Text(l.midiCtlWhatToPlay, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                if (targets.isEmpty)
                  Text(l.midiCtlNothingToPlay, style: const TextStyle(fontSize: 11, color: AppColors.textFaint))
                else
                  DropdownButtonFormField<String>(
                    initialValue: targets.any((t) => t.id == _targetId) ? _targetId : null,
                    isExpanded: true,
                    hint: Text(l.midiCtlPickTarget),
                    items: [
                      for (final t in targets)
                        DropdownMenuItem(
                          value: t.id,
                          child: Text('${_targetKindLabel(t.kind)} · ${t.name}', overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (id) {
                      final match = targets.where((t) => t.id == id);
                      if (match.isEmpty) return;
                      setState(() {
                        _targetId = match.first.id;
                        _targetKind = match.first.kind;
                      });
                    },
                  ),
              ],
              if (_action == MidiActionKind.color) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: Text(l.midiCtlSceneColours),
                      selected: _param == null || _param == 'off',
                      onSelected: (_) => setState(() => _param = 'off'),
                    ),
                    for (final c in liveColors)
                      ChoiceChip(
                        avatar: CircleAvatar(backgroundColor: c.swatch, radius: 7),
                        label: Text(c.label),
                        selected: _param == c.id,
                        onSelected: (_) => setState(() => _param = c.id),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l.commonCancel)),
        FilledButton(onPressed: _complete ? _save : null, child: Text(l.commonSave)),
      ],
    );
  }
}
