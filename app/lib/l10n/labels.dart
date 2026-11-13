/// Localised display names for the app's enums.
///
/// The enums keep their English `label` getters: those are also used where
/// the text is data (exports, the remote API, default names). The UI calls
/// `tr(context.l10n)` instead.
library;

import '../core/audio/beat_detector.dart';
import '../core/generator/program_generator.dart';
import '../core/song/song_generator.dart';
import '../core/song/song_timeline_math.dart';
import '../core/storage/project_snapshot.dart';
import '../core/widgets/fixture_select.dart';
import '../models/chase.dart';
import '../models/control_dock_prefs.dart';
import '../models/fixture_mounting.dart';
import '../models/group_position.dart';
import '../models/movement_fx.dart';
import '../models/output_protocol.dart';
import '../state/audio_providers.dart';
import 'generated/app_localizations.dart';

extension OutputProtocolL10n on OutputProtocol {
  String tr(AppLocalizations l) => this == OutputProtocol.both ? l.enumProtocolBoth : label;
}

extension StageFormationL10n on StageFormation {
  String tr(AppLocalizations l) => switch (this) {
    StageFormation.point => l.enumFormationPoint,
    StageFormation.line => l.enumFormationLine,
    StageFormation.circle => l.enumFormationCircle,
  };
}

extension ControlDockPositionL10n on ControlDockPosition {
  String tr(AppLocalizations l) => switch (this) {
    ControlDockPosition.bottom => l.enumDockBottom,
    ControlDockPosition.right => l.enumDockRight,
  };
}

extension LaneTimingL10n on LaneTiming {
  String tr(AppLocalizations l) => switch (this) {
    LaneTiming.followApp => l.enumLaneFollowDock,
    LaneTiming.onBeat => l.enumLaneOnBeat,
    LaneTiming.free => l.enumLaneFree,
  };
}

extension MountKindL10n on MountKind {
  String tr(AppLocalizations l) => switch (this) {
    MountKind.hanging => l.enumMountHanging,
    MountKind.standing => l.enumMountStanding,
  };
}

extension MovementSpaceL10n on MovementSpace {
  String tr(AppLocalizations l) => switch (this) {
    MovementSpace.panTilt => label,
    MovementSpace.stage => l.enumSpaceStage,
  };
}

extension BeatAdaptSpeedL10n on BeatAdaptSpeed {
  String tr(AppLocalizations l) => switch (this) {
    BeatAdaptSpeed.fast => l.enumAdaptFast,
    BeatAdaptSpeed.normal => l.enumAdaptNormal,
    BeatAdaptSpeed.slow => l.enumAdaptSlow,
    BeatAdaptSpeed.off => l.enumAdaptOff,
  };
}

extension BeatFrequencyBandL10n on BeatFrequencyBand {
  String tr(AppLocalizations l) => switch (this) {
    BeatFrequencyBand.overall => l.enumBandVolume,
    BeatFrequencyBand.kick => label,
    BeatFrequencyBand.kickTight => label,
    BeatFrequencyBand.bass => l.enumBandBass,
    BeatFrequencyBand.mid => l.enumBandMid,
    BeatFrequencyBand.high => l.enumBandHigh,
  };
}

extension StrobeDirectionL10n on StrobeDirection {
  String tr(AppLocalizations l) => switch (this) {
    StrobeDirection.right => l.enumStrobeRight,
    StrobeDirection.left => l.enumStrobeLeft,
    StrobeDirection.bounce => l.enumStrobeBounce,
  };
}

extension FlashColorModeL10n on FlashColorMode {
  String tr(AppLocalizations l) => switch (this) {
    FlashColorMode.single => l.enumFlashSingle,
    FlashColorMode.randomSame => l.enumFlashRandomSame,
    FlashColorMode.randomEach => l.enumFlashRandomEach,
  };
}

extension FixturePatternL10n on FixturePattern {
  String tr(AppLocalizations l) => switch (this) {
    FixturePattern.all => l.enumPatternAll,
    FixturePattern.alternating => l.enumPatternAlternating,
    FixturePattern.oneAtATime => l.enumPatternOneAtATime,
    FixturePattern.randomSubset => l.enumPatternRandomSubset,
  };
}

extension FixtureOrderL10n on FixtureOrder {
  String tr(AppLocalizations l) => switch (this) {
    FixtureOrder.stageLeftToRight => l.enumOrderStageLtr,
    FixtureOrder.stageRightToLeft => l.enumOrderStageRtl,
    FixtureOrder.patch => l.enumOrderPatch,
    FixtureOrder.dmxAddress => l.enumOrderDmx,
    FixtureOrder.manual => l.enumOrderManual,
  };
}

extension ProjectCarryOverL10n on ProjectCarryOver {
  String tr(AppLocalizations l) => switch (this) {
    ProjectCarryOver.empty => l.enumCarryEmpty,
    ProjectCarryOver.fixtures => l.enumCarryFixtures,
    ProjectCarryOver.everything => l.enumCarryEverything,
  };

  String trDescription(AppLocalizations l) => switch (this) {
    ProjectCarryOver.empty => l.enumCarryEmptyHint,
    ProjectCarryOver.fixtures => l.enumCarryFixturesHint,
    ProjectCarryOver.everything => l.enumCarryEverythingHint,
  };
}

extension FixtureTypeFilterL10n on FixtureTypeFilter {
  String tr(AppLocalizations l) => switch (this) {
    FixtureTypeFilter.all => l.enumFilterAll,
    FixtureTypeFilter.rgb => l.enumFilterRgb,
    FixtureTypeFilter.moving => l.enumFilterMoving,
  };
}

extension BeatSourceKindL10n on BeatSourceKind {
  String tr(AppLocalizations l) => switch (this) {
    BeatSourceKind.mic => l.enumSourceMic,
    BeatSourceKind.midi => label,
    BeatSourceKind.osc => label,
  };
}

extension SongStyleL10n on SongStyle {
  String trDescription(AppLocalizations l) => switch (this) {
    SongStyle.club => l.enumStyleClubHint,
    SongStyle.rock => l.enumStyleRockHint,
    SongStyle.chill => l.enumStyleChillHint,
    SongStyle.show => l.enumStyleShowHint,
  };
}

extension SongSnapL10n on SongSnap {
  String tr(AppLocalizations l) => switch (this) {
    SongSnap.off => l.enumSnapFree,
    SongSnap.beat => l.enumSnapBeat,
    SongSnap.half => l.enumSnapHalf,
    SongSnap.bar => l.enumSnapBar,
  };
}
