import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/artnet/artnet_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/fixture_category_style.dart';
import '../../models/builtin_fixtures.dart';
import '../../models/channel_function.dart';
import '../../models/patched_fixture.dart';
import '../../models/universe_config.dart';
import '../../state/artnet_providers.dart';
import '../../state/fixture_providers.dart';

/// A read-only live mirror of the 2D stage layout: fixtures light up with
/// their actual current DMX color, moving heads sweep a beam to match their
/// live pan/tilt, and gobo fixtures show which pattern is selected — so
/// whatever bank/chase is currently running (from anywhere in the app) is
/// visible at a glance from the Dashboard.
class LiveStageView extends ConsumerStatefulWidget {
  const LiveStageView({super.key});

  @override
  ConsumerState<LiveStageView> createState() => _LiveStageViewState();
}

class _LiveStageViewState extends ConsumerState<LiveStageView> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fixtures = ref.watch(patchedFixturesProvider);
    final universes = ref.watch(universesProvider);
    final service = ref.watch(artNetServiceProvider);

    if (fixtures.isEmpty) {
      return const Center(
        child: Text('No patched fixtures yet', style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        return Container(
          width: canvasSize.width,
          height: canvasSize.height,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            children: [
              Center(
                child: Text(
                  'STAGE',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: AppColors.border,
                    letterSpacing: 5,
                  ),
                ),
              ),
              for (final fixture in fixtures)
                _LiveFixtureIcon(
                  key: ValueKey(fixture.id),
                  fixture: fixture,
                  canvasSize: canvasSize,
                  service: service,
                  universe: () {
                    final matches = universes.where((u) => u.id == fixture.universeId);
                    return matches.isEmpty ? null : matches.first;
                  }(),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LiveFixtureIcon extends StatelessWidget {
  final PatchedFixture fixture;
  final Size canvasSize;
  final ArtNetService service;
  final UniverseConfig? universe;

  const _LiveFixtureIcon({
    super.key,
    required this.fixture,
    required this.canvasSize,
    required this.service,
    required this.universe,
  });

  int _valueOf(ChannelFunction function) {
    final universe = this.universe;
    if (universe == null) return 0;
    final idx = fixture.profile.channels.indexWhere((c) => c.function == function);
    if (idx == -1) return 0;
    return service.getChannelValue(universe, fixture.startChannel + fixture.profile.channels[idx].offset);
  }

  @override
  Widget build(BuildContext context) {
    const iconSize = 44.0;
    final maxLeft = (canvasSize.width - iconSize).clamp(0.0, double.infinity);
    final maxTop = (canvasSize.height - iconSize).clamp(0.0, double.infinity);
    final left = (fixture.layoutX * canvasSize.width - iconSize / 2).clamp(0.0, maxLeft);
    final top = (fixture.layoutY * canvasSize.height - iconSize / 2).clamp(0.0, maxTop);

    final functions = fixture.profile.channels.map((c) => c.function).toSet();
    final hasDimmer = functions.contains(ChannelFunction.dimmer);
    final hasColor = functions.any((f) => f.isColorMix);
    final hasPanTilt = functions.any((f) => f.isPanTilt);
    final hasGobo = functions.any((f) => f.isGobo);

    final dimmer = hasDimmer ? _valueOf(ChannelFunction.dimmer) : 255;
    final r = hasColor ? _valueOf(ChannelFunction.red) : 0;
    final g = hasColor ? _valueOf(ChannelFunction.green) : 0;
    final b = hasColor ? _valueOf(ChannelFunction.blue) : 0;
    final w = hasColor ? _valueOf(ChannelFunction.white) : 0;
    final dimmerFrac = dimmer / 255;

    final categoryColor = fixtureCategoryColor(fixture.profile.category);
    Color fillColor;
    double brightness;
    if (hasColor) {
      final wr = (r + w).clamp(0, 255);
      final wg = (g + w).clamp(0, 255);
      final wb = (b + w).clamp(0, 255);
      brightness = (math.max(wr, math.max(wg, wb)) / 255) * dimmerFrac;
      fillColor = Color.fromARGB(
        255,
        (wr * dimmerFrac).round(),
        (wg * dimmerFrac).round(),
        (wb * dimmerFrac).round(),
      );
    } else {
      brightness = dimmerFrac;
      fillColor = Color.lerp(AppColors.panel2, categoryColor, dimmerFrac) ?? categoryColor;
    }
    final active = brightness > 0.03;

    final pan = hasPanTilt ? _valueOf(ChannelFunction.pan) : 0;
    final tilt = hasPanTilt ? _valueOf(ChannelFunction.tilt) : 128;
    final beamAngle = (pan / 255) * 2 * math.pi;
    final beamLength = 10 + (tilt / 255) * 26;

    String? goboLabel;
    if (hasGobo && active) {
      final idx = (_valueOf(ChannelFunction.gobo) ~/ 32).clamp(0, goboPresets.length - 1);
      goboLabel = goboPresets[idx];
    }

    return Positioned(
      left: left,
      top: top,
      child: SizedBox(
        width: iconSize + 28,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: iconSize + 24,
              height: iconSize + 24,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (hasPanTilt && active)
                    Transform.rotate(
                      angle: beamAngle,
                      child: Container(
                        width: 3,
                        height: beamLength,
                        margin: EdgeInsets.only(bottom: iconSize + beamLength),
                        decoration: BoxDecoration(
                          color: fillColor.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [BoxShadow(color: fillColor.withValues(alpha: 0.6), blurRadius: 6)],
                        ),
                      ),
                    ),
                  Container(
                    width: iconSize,
                    height: iconSize,
                    decoration: BoxDecoration(
                      color: AppColors.panel2,
                      shape: BoxShape.circle,
                      border: Border.all(color: active ? fillColor : AppColors.border, width: 2),
                      boxShadow: active
                          ? [BoxShadow(color: fillColor.withValues(alpha: 0.7), blurRadius: 12, spreadRadius: 1)]
                          : null,
                    ),
                    child: Center(
                      child: Container(
                        width: iconSize - 14,
                        height: iconSize - 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: active ? fillColor : AppColors.panel,
                        ),
                        child: !active
                            ? Icon(fixtureCategoryIcon(fixture.profile.category), color: AppColors.textFaint, size: 14)
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(4)),
              child: Text(
                fixture.label,
                style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            if (goboLabel != null)
              Text(
                goboLabel,
                style: const TextStyle(fontSize: 7.5, color: AppColors.accent2, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ),
    );
  }
}
