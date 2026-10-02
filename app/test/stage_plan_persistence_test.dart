import 'package:dmx_controller/core/fixtures/qlcplus_format.dart';
import 'package:dmx_controller/models/artnet_settings.dart';
import 'package:dmx_controller/models/builtin_fixtures.dart';
import 'package:dmx_controller/models/channel_capability.dart';
import 'package:dmx_controller/models/channel_function.dart';
import 'package:dmx_controller/models/fixture_channel.dart';
import 'package:dmx_controller/models/fixture_mounting.dart';
import 'package:dmx_controller/models/fixture_profile.dart';
import 'package:dmx_controller/models/pan_tilt.dart';
import 'package:dmx_controller/models/patched_fixture.dart';
import 'package:dmx_controller/models/position_preset.dart';
import 'package:dmx_controller/models/project_data.dart';
import 'package:dmx_controller/models/stage_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final beam = builtInFixtureProfiles.firstWhere((p) => p.id == 'builtin-moving-head-beam');

  test('the stage plan, saved positions and head rigging survive a save and load', () {
    final data = ProjectData(
      name: 'Club',
      settings: const ArtNetSettings(),
      universes: const [],
      customFixtureProfiles: const [],
      patchedFixtures: [
        PatchedFixture(
          id: 'mh1',
          label: 'MH 1',
          profile: beam,
          universeId: 'u',
          startChannel: 0,
          mounting: const FixtureMounting(
            mount: MountKind.standing,
            heightM: 0.5,
            facingDeg: 180,
            invertPan: true,
            panOffsetDeg: -2.5,
          ),
        ),
      ],
      scenes: const [],
      banks: const [],
      chases: const [],
      stagePlan: const StagePlan(
        widthM: 10,
        depthM: 7,
        targets: [AimTarget(id: 't', name: 'Mirror ball', x: 0.5, y: 0.4, heightM: 3.2)],
      ),
      positionPresets: const [
        PositionPreset(id: 'p', name: 'Audience', perFixture: {'mh1': PanTilt(100, 200)}),
      ],
    );

    final back = ProjectData.fromJson(data.toJson(), builtIns: builtInFixtureProfiles);
    expect(back.stagePlan.widthM, 10);
    expect(back.stagePlan.depthM, 7);
    expect(back.stagePlan.targets.single.name, 'Mirror ball');
    expect(back.stagePlan.targets.single.heightM, 3.2);
    expect(back.positionPresets.single.perFixture, {'mh1': const PanTilt(100, 200)});
    final mounting = back.patchedFixtures.single.mounting;
    expect(mounting.mount, MountKind.standing);
    expect(mounting.heightM, 0.5);
    expect(mounting.facingDeg, 180);
    expect(mounting.invertPan, isTrue);
    expect(mounting.panOffsetDeg, -2.5);
  });

  test('a project saved before any of this loads with sensible defaults', () {
    final back = ProjectData.fromJson({
      'name': 'Old',
      'patchedFixtures': [
        {'id': 'mh1', 'label': 'MH 1', 'profileId': beam.id, 'universeId': 'u', 'startChannel': 0},
      ],
    }, builtIns: builtInFixtureProfiles);
    expect(back.stagePlan.widthM, StagePlan.defaultWidthM);
    expect(back.positionPresets, isEmpty);
    expect(back.patchedFixtures.single.mounting.isDefault, isTrue);
  });

  test('profiles keep their pan/tilt range, and old ones get the usual 540/270', () {
    final custom = FixtureProfile(
      id: 'x',
      name: 'Beam',
      category: FixtureCategory.movingHead,
      channels: const [FixtureChannel(offset: 0, function: ChannelFunction.pan)],
      panRangeDeg: 540,
      tiltRangeDeg: 180,
    );
    expect(FixtureProfile.fromJson(custom.toJson()).tiltRangeDeg, 180);
    final old = FixtureProfile.fromJson({'id': 'o', 'name': 'Old', 'category': 'movingHead', 'channels': []});
    expect(old.panRangeDeg, 540);
    expect(old.tiltRangeDeg, 270);
  });

  test('a capability keeps its swatch colour and gobo picture', () {
    const capability = ChannelCapability(min: 0, max: 7, label: 'Slot 1', colorHex: '#00BCD4', glyph: 'star');
    final back = ChannelCapability.fromJson(capability.toJson());
    expect(back.colorHex, '#00BCD4');
    expect(back.glyph, 'star');
    expect(capability.copyWith(label: 'Cyan').colorHex, '#00BCD4');
  });

  test('channel keys keep same-function channels apart', () {
    expect(channelKeysFor(beam.channels), contains('generic:reset'));
    expect(channelKeysFor(beam.channels), contains('generic:function'));
    final twin = channelKeysFor(const [
      FixtureChannel(offset: 0, function: ChannelFunction.colorWheel),
      FixtureChannel(offset: 1, function: ChannelFunction.colorWheel),
    ]);
    expect(twin, ['colorWheel', 'colorWheel#1']);
  });

  test('QLC+ prism, frost and pan/tilt speed channels get their own functions', () {
    expect(functionFromGroupAndName('Prism', 'Prism'), ChannelFunction.prism);
    expect(functionFromGroupAndName('Prism', 'Prism rotation'), ChannelFunction.prismRotation);
    expect(functionFromGroupAndName('Beam', 'Frost'), ChannelFunction.frost);
    expect(functionFromGroupAndName('Speed', 'Pan/Tilt speed'), ChannelFunction.panTiltSpeed);
    expect(functionFromGroupAndName('Maintenance', 'Pan/tilt speed'), ChannelFunction.panTiltSpeed);
    expect(functionFromGroupAndName('Pan', 'Pan'), ChannelFunction.pan);
  });
}
