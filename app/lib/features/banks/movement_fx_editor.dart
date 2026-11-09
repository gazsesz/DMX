import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/movement/movement_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/log_scale.dart';
import '../../core/widgets/pan_tilt_pad.dart';
import '../../models/bank.dart';
import '../../models/group_position.dart';
import '../../models/movement_fx.dart';
import '../../state/bank_providers.dart';
import '../../state/fixture_group_providers.dart';
import '../../state/fixture_providers.dart';
import '../../l10n/l10n.dart';

const _lapScale = LogScale(min: 0.5, max: 60.0, inverted: true);

/// The editor for a Movement FX bank: pick the path, size it, set its speed
/// and say which heads move. Every change goes straight to the bank, and a
/// running bank follows it on the next tick — nothing needs restarting.
class MovementFxEditor extends ConsumerWidget {
  final Bank bank;

  const MovementFxEditor({super.key, required this.bank});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fx = bank.fx;
    if (fx == null) return const SizedBox.shrink();
    final groups = ref.watch(fixtureGroupsProvider);
    final fixtures = ref.watch(patchedFixturesProvider);
    final movers = movementHeads(
      const MovementFx(),
      fixtures,
      const [],
    ).map((h) => h.fixture).toList();
    void update(MovementFx next) =>
        ref.read(banksProvider.notifier).setFx(bank.id, next);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(context.l10n.fxShape),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final shape in MovementShape.values)
                ChoiceChip(
                  label: Text(shape.label),
                  selected: fx.shape == shape,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => update(fx.copyWith(shape: shape)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 130,
            child: _PathPreview(fx: fx, heads: movers.isEmpty ? 3 : math.min(movers.length, 6)),
          ),
          const SizedBox(height: 8),
          _label(context.l10n.fxSpeed),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(context.l10n.fxLockToBeat),
            subtitle: Text(
              fx.beatLocked
                  ? context.l10n.fxLockedHint(_beats(fx.beats))
                  : context.l10n.fxFreeRunning,
              style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
            ),
            value: fx.beatLocked,
            onChanged: (v) => update(fx.copyWith(beatLocked: v)),
          ),
          if (fx.beatLocked)
            Wrap(
              spacing: 8,
              children: [
                for (final beats in MovementFx.beatChoices)
                  ChoiceChip(
                    label: Text(context.l10n.fxBeats(_beats(beats))),
                    selected: fx.beats == beats,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => update(fx.copyWith(beats: beats)),
                  ),
              ],
            )
          else
            _slider(
              context.l10n.fxLapTime,
              _lapScale.positionOf(fx.periodSec),
              '${fx.periodSec.toStringAsFixed(fx.periodSec < 10 ? 1 : 0)} s',
              // Right is faster, as on the dock's step speed.
              (v) => update(
                fx.copyWith(
                  periodSec: double.parse(
                    _lapScale.valueAt(v).toStringAsFixed(2),
                  ),
                ),
              ),
              min: 0,
              max: 1,
            ),
          Wrap(
            spacing: 16,
            children: [
              _toggle(
                context.l10n.fxReverse,
                fx.reverse,
                (v) => update(fx.copyWith(reverse: v)),
              ),
              _toggle(
                context.l10n.fxMirror,
                fx.mirror,
                (v) => update(fx.copyWith(mirror: v)),
              ),
            ],
          ),
          _slider(
            context.l10n.fxWave,
            fx.phaseSpread,
            fx.phaseSpread == 0
                ? context.l10n.fxTogether
                : context.l10n.fxPercentOfLap((fx.phaseSpread * 100).round()),
            (v) => update(fx.copyWith(phaseSpread: v)),
          ),
          const SizedBox(height: 4),
          _label(context.l10n.fxPath),
          SegmentedButton<MovementSpace>(
            segments: [
              for (final space in MovementSpace.values)
                ButtonSegment(value: space, label: Text(space.label)),
            ],
            selected: {fx.space},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) => update(fx.copyWith(space: s.first)),
          ),
          const SizedBox(height: 4),
          if (fx.space == MovementSpace.panTilt) ...[
            _slider(
              context.l10n.fxWidth,
              fx.sizePanDeg / 180,
              '±${fx.sizePanDeg.round()}°',
              (v) => update(fx.copyWith(sizePanDeg: v * 180)),
            ),
            _slider(
              context.l10n.fxHeight,
              fx.sizeTiltDeg / 90,
              '±${fx.sizeTiltDeg.round()}°',
              (v) => update(fx.copyWith(sizeTiltDeg: v * 90)),
            ),
            _label(context.l10n.fxCentre),
            Center(
              child: SizedBox(
                width: 220,
                height: 150,
                child: PanTiltPad(
                  value: fx.center,
                  panRangeDeg: 540,
                  tiltRangeDeg: 270,
                  onChanged: (v) => update(fx.copyWith(center: v)),
                ),
              ),
            ),
          ] else ...[
            Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                context.l10n.fxStagePlanHint,
                style: TextStyle(fontSize: 11, color: AppColors.textFaint),
              ),
            ),
            _slider(
              context.l10n.fxWidth,
              fx.sizeXM / 10,
              '±${fx.sizeXM.toStringAsFixed(1)} m',
              (v) => update(fx.copyWith(sizeXM: v * 10)),
            ),
            _slider(
              context.l10n.fxDepth,
              fx.sizeYM / 10,
              '±${fx.sizeYM.toStringAsFixed(1)} m',
              (v) => update(fx.copyWith(sizeYM: v * 10)),
            ),
            _slider(
              context.l10n.fxCentreAcross,
              fx.stageCenter.x,
              '${(fx.stageCenter.x * 100).round()}%',
              (v) => update(
                fx.copyWith(stageCenter: StagePoint(v, fx.stageCenter.y)),
              ),
            ),
            _slider(
              context.l10n.fxCentreDepth,
              fx.stageCenter.y,
              '${(fx.stageCenter.y * 100).round()}%',
              (v) => update(
                fx.copyWith(stageCenter: StagePoint(fx.stageCenter.x, v)),
              ),
            ),
            _slider(
              context.l10n.fxPlaneHeight,
              fx.aimHeightM / 5,
              '${fx.aimHeightM.toStringAsFixed(1)} m',
              (v) => update(fx.copyWith(aimHeightM: v * 5)),
            ),
          ],
          _slider(
            context.l10n.fxRotate,
            (fx.rotationDeg + 180) / 360,
            '${fx.rotationDeg.round()}°',
            (v) => update(
              fx.copyWith(rotationDeg: (v * 360 - 180).roundToDouble()),
            ),
          ),
          if (fx.space == MovementSpace.panTilt)
            _slider(
              context.l10n.fxFan,
              fx.fanPanDeg / 90,
              fx.fanPanDeg == 0 ? context.l10n.commonOff : context.l10n.fxFanDeg(fx.fanPanDeg.round()),
              (v) => update(fx.copyWith(fanPanDeg: (v * 90).roundToDouble())),
            )
          else
            _slider(
              context.l10n.fxFan,
              fx.fanXM / 5,
              fx.fanXM == 0 ? context.l10n.commonOff : context.l10n.fxFanM(fx.fanXM.toStringAsFixed(1)),
              (v) => update(fx.copyWith(fanXM: double.parse((v * 5).toStringAsFixed(1)))),
            ),
          const SizedBox(height: 4),
          _label(context.l10n.fxLook),
          _LookSection(fx: fx, banks: ref.watch(banksProvider), onChanged: update),
          const SizedBox(height: 4),
          _label(context.l10n.fxHeads),
          Text(
            fx.groupIds.isEmpty && fx.fixtureIds.isEmpty
                ? context.l10n.fxEveryHead(movers.length)
                : context.l10n.fxOnlyPicked,
            style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final group in groups)
                FilterChip(
                  avatar: const Icon(Icons.folder_outlined, size: 14),
                  label: Text(group.name),
                  selected: fx.groupIds.contains(group.id),
                  visualDensity: VisualDensity.compact,
                  onSelected: (on) => update(
                    fx.copyWith(groupIds: _toggled(fx.groupIds, group.id, on)),
                  ),
                ),
              for (final fixture in movers)
                FilterChip(
                  label: Text(fixture.label),
                  selected: fx.fixtureIds.contains(fixture.id),
                  visualDensity: VisualDensity.compact,
                  onSelected: (on) => update(
                    fx.copyWith(
                      fixtureIds: _toggled(fx.fixtureIds, fixture.id, on),
                    ),
                  ),
                ),
            ],
          ),
          if (movers.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                context.l10n.fxNoMovers,
                style: TextStyle(fontSize: 11, color: AppColors.accent),
              ),
            ),
        ],
      ),
    );
  }

  static Set<String> _toggled(Set<String> ids, String id, bool on) =>
      on ? {...ids, id} : ids.difference({id});

  static String _beats(double beats) => beats == beats.roundToDouble()
      ? beats.round().toString()
      : beats.toString();

  static Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 2),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 10.5,
        letterSpacing: 1,
        color: AppColors.textFaint,
      ),
    ),
  );

  static Widget _toggle(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Switch(value: value, onChanged: onChanged),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );

  static Widget _slider(
    String label,
    double value,
    String readout,
    ValueChanged<double> onChanged, {
    double min = 0,
    double max = 1,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 118,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textFaint),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 78,
          child: Text(
            readout,
            style: appMonoStyle(fontSize: 10.5, color: AppColors.textFaint),
          ),
        ),
      ],
    );
  }
}

/// The path as the heads will draw it, live: one dot per head (up to six)
/// running round at the effect's own speed, with the wave, fan, mirror,
/// direction and rotation applied the way the player applies them. Beat-locked
/// effects are shown at 120 BPM.
class _PathPreview extends StatefulWidget {
  final MovementFx fx;
  final int heads;

  const _PathPreview({required this.fx, required this.heads});

  @override
  State<_PathPreview> createState() => _PathPreviewState();
}

class _PathPreviewState extends State<_PathPreview> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _seconds = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) => _seconds.value = elapsed.inMicroseconds / 1e6)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _PathPainter(widget.fx, widget.heads, _seconds),
    size: Size.infinite,
  );
}

const _headColors = [
  AppColors.accent,
  AppColors.accent2,
  Color(0xFF22C55E),
  Color(0xFFA78BFA),
  Color(0xFFF472B6),
  Color(0xFF60A5FA),
];

class _PathPainter extends CustomPainter {
  final MovementFx fx;
  final int heads;
  final ValueNotifier<double> seconds;

  _PathPainter(this.fx, this.heads, this.seconds) : super(repaint: seconds);

  /// Where the effect is in its lap [t] seconds in.
  double _phase(double t) {
    final lap = fx.beatLocked ? fx.beats * 0.5 : fx.periodSec;
    return lap <= 0 ? 0 : (t / lap) % 1.0;
  }

  Offset _at(int head, double phase) {
    final (x, y) = movementOffset(fx, head, heads, phase, rightOfCentre: head >= heads / 2);
    return Offset(x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      Paint()
        ..color = AppColors.textFaint.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke,
    );

    // Each head's whole lap, for the scale and the faint track.
    const steps = 120;
    final tracks = [
      for (var h = 0; h < heads; h++) [for (var i = 0; i <= steps; i++) _at(h, i / steps)],
    ];
    final points = tracks.expand((t) => t);
    final extentX = points.fold<double>(1e-6, (m, p) => math.max(m, p.dx.abs()));
    final extentY = points.fold<double>(1e-6, (m, p) => math.max(m, p.dy.abs()));
    // One scale for both axes, so a circle stays round, as large as the box allows.
    final scale = math.min((size.width / 2 - 12) / extentX, (size.height / 2 - 12) / extentY);
    final centre = size.center(Offset.zero);
    Offset toCanvas(Offset p) => centre + Offset(p.dx * scale, p.dy * scale);

    // A fan or a wide path is wider than tall; use the whole box.
    for (var h = 0; h < heads; h++) {
      final color = _headColors[h % _headColors.length];
      final path = Path();
      for (var i = 0; i < tracks[h].length; i++) {
        final c = toCanvas(tracks[h][i]);
        i == 0 ? path.moveTo(c.dx, c.dy) : path.lineTo(c.dx, c.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    final phase = _phase(seconds.value);
    final lapSeconds = fx.beatLocked ? fx.beats * 0.5 : fx.periodSec;
    for (var h = 0; h < heads; h++) {
      final color = _headColors[h % _headColors.length];
      // A short tail, so the direction and speed read at a glance.
      for (var k = 6; k >= 0; k--) {
        final back = lapSeconds <= 0 ? 0.0 : k * 0.04 / lapSeconds;
        final p = toCanvas(_at(h, (phase - (fx.reverse ? -back : back)) % 1.0));
        canvas.drawCircle(p, k == 0 ? 5 : 4.0 - k * 0.45, Paint()..color = color.withValues(alpha: k == 0 ? 1 : 0.5 - k * 0.06));
      }
    }
  }

  @override
  bool shouldRepaint(_PathPainter old) => old.fx != fx || old.heads != heads;
}

/// The scenes (colours, gobo, dimmer…) that play alongside the path, picked
/// from the scene banks. They step on the dock's Hold/Fade and beat sync, or
/// at a pace of their own.
class _LookSection extends StatelessWidget {
  final MovementFx fx;
  final List<Bank> banks;
  final ValueChanged<MovementFx> onChanged;

  const _LookSection({required this.fx, required this.banks, required this.onChanged});

  Future<void> _pick(BuildContext context) async {
    final candidates = banks.where((b) => !b.isMovementFx).toList();
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.panel,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(context.l10n.fxLookBank, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            if (candidates.isEmpty)
              ListTile(title: Text(context.l10n.fxNoSceneBanks)),
            for (final bank in candidates)
              ListTile(
                dense: true,
                leading: const Icon(Icons.palette_outlined, color: AppColors.accent2),
                title: Text(bank.name),
                subtitle: Text(context.l10n.fxScenesCount(bank.sceneSlots.where((s) => s != null).length)),
                selected: bank.id == fx.lookBankId,
                onTap: () => Navigator.pop(context, bank.id),
              ),
          ],
        ),
      ),
    );
    if (picked != null) onChanged(fx.copyWith(lookBankId: picked));
  }

  @override
  Widget build(BuildContext context) {
    final bank = banks.where((b) => b.id == fx.lookBankId).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                fx.lookBankId == null
                    ? context.l10n.fxLookNone
                    : bank == null
                        ? context.l10n.fxLookGone
                        : bank.name,
                style: TextStyle(fontSize: 12, color: bank == null ? AppColors.textFaint : AppColors.text),
              ),
            ),
            TextButton(onPressed: () => _pick(context), child: Text(fx.lookBankId == null ? context.l10n.fxPickBank : context.l10n.fxChange)),
            if (fx.lookBankId != null)
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                tooltip: context.l10n.fxNoLook,
                onPressed: () => onChanged(fx.copyWith(clearLook: true)),
              ),
          ],
        ),
        if (fx.lookBankId != null) ...[
          Text(
            context.l10n.fxLookPanTiltIgnored,
            style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
          ),
          SizedBox(height: 4),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(context.l10n.fxDockHoldFade)),
              ButtonSegment(value: true, label: Text(context.l10n.fxOwnTiming)),
            ],
            selected: {fx.lookOwnTiming},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) => onChanged(fx.copyWith(lookOwnTiming: s.first)),
          ),
          if (!fx.lookOwnTiming)
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                context.l10n.fxLookFollowsDock,
                style: TextStyle(fontSize: 11, color: AppColors.textFaint),
              ),
            )
          else ...[
            MovementFxEditor._slider(
              context.l10n.fxLookHold,
              holdTimeScale.positionOf(fx.lookHoldMs / 1000),
              '${(fx.lookHoldMs / 1000).toStringAsFixed(2)} s',
              (v) => onChanged(fx.copyWith(lookHoldMs: (holdTimeScale.valueAt(v) * 1000).round().clamp(20, 60000))),
            ),
            MovementFxEditor._slider(
              context.l10n.fxLookFade,
              fadeTimeScale.positionOf(fx.lookFadeMs / 1000),
              '${(fx.lookFadeMs / 1000).toStringAsFixed(2)} s',
              (v) => onChanged(fx.copyWith(lookFadeMs: (fadeTimeScale.valueAt(v) * 1000).round().clamp(0, 120000))),
            ),
          ],
        ],
      ],
    );
  }
}
