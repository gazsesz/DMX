import 'package:dmx_controller/models/scene.dart';
import 'package:flutter_test/flutter_test.dart';

/// `fixtureGroups` is what the Scene Editor writes down to remember exactly
/// how the user last split a scene's fixtures into groups, rather than
/// re-inferring it from matching channel values on reopen (which silently
/// re-merges two groups that happen to share a colour, or fails to notice a
/// group that hasn't had its colour changed yet) — see `SceneEditorScreen`.
void main() {
  test('a scene with no grouping saved omits the field entirely', () {
    const scene = Scene(id: 's1', name: 'Plain', fixtureValues: {'f1': [255]});
    expect(scene.fixtureGroups, isNull);
    expect(scene.toJson().containsKey('fixtureGroups'), isFalse);
  });

  test('round-trips explicit groups through JSON', () {
    const scene = Scene(
      id: 's1',
      name: 'Mixed',
      fixtureValues: {'f1': [255, 0, 0], 'f2': [255, 0, 0], 'f3': [0, 0, 255]},
      fixtureGroups: [
        ['f1', 'f2'],
        ['f3'],
      ],
    );
    final restored = Scene.fromJson(scene.toJson());
    expect(restored.fixtureGroups, [
      ['f1', 'f2'],
      ['f3'],
    ]);
  });

  test('a scene saved before grouping existed loads with none', () {
    final restored = Scene.fromJson({
      'id': 's1',
      'name': 'Old',
      'fixtureValues': {'f1': [255]},
    });
    expect(restored.fixtureGroups, isNull);
  });

  test('copyWith leaves the saved grouping alone unless a new one is given', () {
    const scene = Scene(
      id: 's1',
      name: 'Mixed',
      fixtureValues: {'f1': [1]},
      fixtureGroups: [['f1']],
    );
    final renamed = scene.copyWith(name: 'Renamed');
    expect(renamed.fixtureGroups, [['f1']]);
  });
}
