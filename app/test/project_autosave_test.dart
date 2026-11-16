import 'dart:io';

import 'package:dmx_controller/core/storage/project_storage.dart';
import 'package:dmx_controller/state/autosave_providers.dart';
import 'package:dmx_controller/state/live_providers.dart';
import 'package:dmx_controller/state/project_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStorage extends ProjectStorage {
  final writes = <String, String>{};
  int count = 0;

  @override
  Future<File> saveEncoded(String name, String json) async {
    count++;
    writes[name] = json;
    return File(name);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeStorage storage;
  late ProviderContainer c;

  setUp(() {
    storage = _FakeStorage();
    c = ProviderContainer(overrides: [
      projectStorageProvider.overrideWithValue(storage),
      autoSaveDelayProvider.overrideWithValue(const Duration(milliseconds: 20)),
    ]);
    c.read(currentProjectNameProvider.notifier).state = 'Club';
    c.read(projectAutoSaveProvider.notifier).markSaved();
  });

  tearDown(() => c.dispose());

  void bumpLevel(double amount) {
    final grid = c.read(liveGridProvider);
    c.read(liveGridProvider.notifier).updateLane(grid.lane('level')!.copyWith(amount: amount));
  }

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

  test('tracks edits but writes nothing until enabled', () async {
    bumpLevel(0.3);
    expect(c.read(projectAutoSaveProvider), ProjectSaveState.dirty);
    await settle();
    expect(storage.count, 0);
  });

  test('a Mixer edit is written a moment later, then shows as saved', () async {
    c.read(projectAutoSaveProvider.notifier).enable();
    bumpLevel(0.3);
    bumpLevel(0.4);
    expect(c.read(projectAutoSaveProvider), ProjectSaveState.dirty);
    await settle();
    expect(storage.count, 1, reason: 'a burst of edits is one write');
    expect(storage.writes['Club'], contains('"liveGrid"'));
    expect(storage.writes['Club'], contains('0.4'));
    expect(c.read(projectAutoSaveProvider), ProjectSaveState.saved);
  });

  test('an edit undone before the save writes nothing', () async {
    c.read(projectAutoSaveProvider.notifier).enable();
    final before = c.read(liveGridProvider).lane('level')!.amount;
    bumpLevel(0.25);
    bumpLevel(before);
    await settle();
    expect(storage.count, 0);
    expect(c.read(projectAutoSaveProvider), ProjectSaveState.saved);
  });

  test('leaving the app saves straight away', () async {
    c.read(projectAutoSaveProvider.notifier).enable();
    bumpLevel(0.7);
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await Future<void>.delayed(Duration.zero);
    expect(storage.count, 1);
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle();
    expect(storage.count, 1);
  });

  test('the Save button writes even when nothing changed', () async {
    expect(await c.read(projectAutoSaveProvider.notifier).saveNow(force: true), isTrue);
    expect(storage.count, 1);
  });
}
