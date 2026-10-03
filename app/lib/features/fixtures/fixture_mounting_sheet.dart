import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/positions/aim.dart';
import '../../core/positions/group_positions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/channel_capability.dart';
import '../../models/channel_function.dart';
import '../../models/fixture_mounting.dart';
import '../../models/group_position.dart';
import '../../models/pan_tilt.dart';
import '../../models/patched_fixture.dart';
import '../../state/artnet_providers.dart';
import '../../state/fixture_providers.dart';
import '../../state/stage_providers.dart';

/// Opens the rigging and calibration sheet for one moving head.
Future<void> showFixtureMountingSheet(
  BuildContext context,
  String fixtureId, {
  StagePoint? mark,
  double markHeightM = 0,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.panel,
    builder: (context) =>
        _FixtureMountingSheet(fixtureId: fixtureId, mark: mark, markHeightM: markHeightM, onChanged: onChanged),
  );
}

/// How a moving head is rigged (hung or standing, how high, which way it
/// faces) and a one-spot calibration, so the Scene editor's stage view can
/// aim it at a spot on the plan.
///
/// Calibration works the way you'd do it with a desk and a tape mark: the
/// head is sent to where the maths thinks the middle of the stage floor is,
/// you nudge it until the beam really sits on the mark, and the difference
/// is kept as an offset for every aim after that.
class _FixtureMountingSheet extends ConsumerStatefulWidget {
  final String fixtureId;

  /// Where the beam is held for calibration: a spot on the plan (normalised),
  /// at [markHeightM] above the floor. Null is the middle of the stage floor.
  final StagePoint? mark;
  final double markHeightM;

  /// Opened from an editor that already puts the head on its target live:
  /// every change just tells it to do so again, instead of this sheet driving
  /// the head itself.
  final VoidCallback? onChanged;

  const _FixtureMountingSheet({required this.fixtureId, this.mark, this.markHeightM = 0, this.onChanged});

  @override
  ConsumerState<_FixtureMountingSheet> createState() => _FixtureMountingSheetState();
}

class _FixtureMountingSheetState extends ConsumerState<_FixtureMountingSheet> {
  late final TextEditingController _heightController;

  /// Whether the head is currently being held on the calibration mark.
  bool _calibrating = false;

  PatchedFixture? get _fixture =>
      ref.read(patchedFixturesProvider).where((f) => f.id == widget.fixtureId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _heightController = TextEditingController(text: _fixture?.mounting.heightM.toStringAsFixed(2) ?? '3.00');
  }

  @override
  void dispose() {
    _heightController.dispose();
    super.dispose();
  }

  void _update(FixtureMounting Function(FixtureMounting) change) {
    final fixture = _fixture;
    if (fixture == null) return;
    ref.read(patchedFixturesProvider.notifier).setMounting(fixture.id, change(fixture.mounting));
    if (widget.onChanged != null) {
      widget.onChanged!();
    } else if (_calibrating) {
      _sendToMark();
    }
  }

  /// Aims the head at the middle of the stage floor, lamp open.
  void _sendToMark() {
    final fixture = _fixture;
    if (fixture == null) return;
    if (widget.onChanged != null) {
      widget.onChanged!();
      setState(() => _calibrating = true);
      return;
    }
    final stage = ref.read(stagePlanProvider);
    final aimed = aimAt(
      aimRigFor(fixture, stage),
      tx: (widget.mark?.x ?? 0.5) * stage.widthM,
      ty: (widget.mark?.y ?? 0.5) * stage.depthM,
      tz: widget.markHeightM,
      previous: PanTilt.center,
    );
    final service = ref.read(artNetServiceProvider);
    final universe = ref.read(universesProvider).where((u) => u.id == fixture.universeId).firstOrNull;
    if (universe == null || !service.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connect to the Art-Net node first to see the beam')),
      );
      return;
    }
    for (final channel in fixture.profile.channels) {
      final int? value = switch (channel.function) {
        ChannelFunction.pan => aimed.position.panCoarse,
        ChannelFunction.panFine => aimed.position.panFine,
        ChannelFunction.tilt => aimed.position.tiltCoarse,
        ChannelFunction.tiltFine => aimed.position.tiltFine,
        ChannelFunction.dimmer => 255,
        ChannelFunction.strobe => _openShutterValue(channel.capabilities),
        _ => null,
      };
      if (value != null) {
        service.setChannel(universe, fixture.startChannel + channel.offset, value, send: false);
      }
    }
    service.flush(universe);
    setState(() => _calibrating = true);
  }

  /// The shutter's "open" value when the profile names one; otherwise the
  /// strobe channel is left as it is, since 255 on one fixture is "open"
  /// and on the next is the fastest strobe.
  int? _openShutterValue(List<ChannelCapability> capabilities) {
    for (final c in capabilities) {
      if (c.label.toLowerCase().contains('open')) return c.pickValue;
    }
    return null;
  }

  void _nudge({double pan = 0, double tilt = 0}) {
    _update((m) => m.copyWith(panOffsetDeg: m.panOffsetDeg + pan, tiltOffsetDeg: m.tiltOffsetDeg + tilt));
    if (!_calibrating && widget.onChanged == null) _sendToMark();
  }

  @override
  Widget build(BuildContext context) {
    final fixture = ref.watch(patchedFixturesProvider).where((f) => f.id == widget.fixtureId).firstOrNull;
    if (fixture == null) return const SizedBox.shrink();
    final mounting = fixture.mounting;
    final stage = ref.watch(stagePlanProvider);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
          children: [
            Text(fixture.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            Text(
              '${fixture.profile.qualifiedName} · pan ${fixture.profile.panRangeDeg}° / tilt ${fixture.profile.tiltRangeDeg}°',
              style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
            ),
            const SizedBox(height: 16),
            _label('MOUNTING'),
            SegmentedButton<MountKind>(
              showSelectedIcon: false,
              segments: [for (final kind in MountKind.values) ButtonSegment(value: kind, label: Text(kind.label))],
              selected: {mounting.mount},
              onSelectionChanged: (s) {
                final kind = s.first;
                // Swap in the other mount's usual height unless one was typed.
                final defaultHeight = kind == MountKind.hanging
                    ? FixtureMounting.defaultHangingHeightM
                    : FixtureMounting.defaultStandingHeightM;
                final keepHeight = mounting.heightM != FixtureMounting.defaultHangingHeightM &&
                    mounting.heightM != FixtureMounting.defaultStandingHeightM;
                final height = keepHeight ? mounting.heightM : defaultHeight;
                _heightController.text = height.toStringAsFixed(2);
                _update((m) => m.copyWith(mount: kind, heightM: height));
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _heightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: mounting.mount == MountKind.hanging ? 'Height of the head (truss trim)' : 'Height of the head',
                suffixText: 'm',
              ),
              onChanged: (text) {
                final value = double.tryParse(text.trim().replaceAll(',', '.'));
                if (value != null && value >= 0 && value <= 50) _update((m) => m.copyWith(heightM: value));
              },
            ),
            const SizedBox(height: 14),
            _label('PAN CENTRE FACES'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (deg, name) in [(0.0, 'Audience'), (90.0, 'Right'), (180.0, 'Upstage'), (270.0, 'Left')])
                  ChoiceChip(
                    label: Text(name, style: const TextStyle(fontSize: 11.5)),
                    selected: mounting.facingDeg == deg,
                    onSelected: (_) => _update((m) => m.copyWith(facingDeg: deg)),
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: mounting.facingDeg % 360,
                    max: 345,
                    divisions: 23,
                    onChanged: (v) => _update((m) => m.copyWith(facingDeg: v)),
                  ),
                ),
                SizedBox(
                  width: 46,
                  child: Text('${mounting.facingDeg.round()}°', textAlign: TextAlign.right, style: appMonoStyle(fontSize: 12)),
                ),
              ],
            ),
            const Text(
              'Where the beam points on the plan with pan at the middle of its travel. '
              'Right and left are as the audience sees the stage.',
              style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Invert pan'),
              subtitle: const Text('The head turns the opposite way to the plan'),
              value: mounting.invertPan,
              onChanged: (v) => _update((m) => m.copyWith(invertPan: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Invert tilt'),
              subtitle: const Text('The beam lifts the wrong way'),
              value: mounting.invertTilt,
              onChanged: (v) => _update((m) => m.copyWith(invertTilt: v)),
            ),
            const SizedBox(height: 10),
            _label('CALIBRATION'),
            Text(
              '${widget.mark == null ? 'Put a mark on the floor in the middle of the stage' : 'Put something at the spot you are aiming at in the Scene editor'}'
              ' '
              '(${((widget.mark?.x ?? 0.5) * stage.widthM).toStringAsFixed(1)} m from the left edge, '
              '${((widget.mark?.y ?? 0.5) * stage.depthM).toStringAsFixed(1)} m from the back'
              '${widget.markHeightM > 0 ? ', ${widget.markHeightM.toStringAsFixed(1)} m up' : ''}). '
              'Send the head there, nudge it until the beam sits on the mark, and you\'re done — '
              'every nudge is saved as you go.',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textDim),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _sendToMark,
              icon: const Icon(Icons.my_location, size: 18),
              label: Text(_calibrating ? 'Send to the mark again' : 'Aim at the mark'),
            ),
            const SizedBox(height: 10),
            _nudgeRow('Pan', (d) => _nudge(pan: d)),
            _nudgeRow('Tilt', (d) => _nudge(tilt: d)),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Offset: pan ${_signed(mounting.panOffsetDeg)}° · tilt ${_signed(mounting.tiltOffsetDeg)}°',
                    style: appMonoStyle(fontSize: 11.5, color: AppColors.textDim),
                  ),
                ),
                if (mounting.isCalibrated)
                  TextButton(
                    onPressed: () => _update((m) => m.copyWith(panOffsetDeg: 0, tiltOffsetDeg: 0)),
                    child: const Text('Reset'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _signed(double value) => '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)}';

  Widget _nudgeRow(String axis, ValueChanged<double> nudge) {
    Widget button(double step) => Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 34)),
          onPressed: () => nudge(step),
          child: Text('${step > 0 ? '+' : '−'}${step.abs() < 1 ? step.abs().toStringAsFixed(1) : step.abs().toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 11.5)),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(width: 36, child: Text(axis, style: const TextStyle(fontSize: 11.5, color: AppColors.textDim))),
          for (final step in const [-5.0, -1.0, -0.2, 0.2, 1.0, 5.0]) button(step),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textFaint)),
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
