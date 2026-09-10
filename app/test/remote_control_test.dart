import 'dart:convert';
import 'dart:io';

import 'package:dmx_controller/core/remote/remote_control_server.dart';
import 'package:dmx_controller/models/bank.dart';
import 'package:dmx_controller/models/chase.dart';
import 'package:dmx_controller/state/bank_providers.dart';
import 'package:dmx_controller/models/dashboard_trigger.dart';
import 'package:dmx_controller/models/smart_program.dart';
import 'package:dmx_controller/state/chase_providers.dart';
import 'package:dmx_controller/state/dashboard_providers.dart';
import 'package:dmx_controller/state/smart_program_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The remote endpoint is what a watch macro talks to, so it has to be
/// verifiable without a watch: spin it up against a real container and make
/// actual HTTP calls.
void main() {
  // Stopping/blacking out reaches the beat detector, which builds an
  // AudioRecorder over a platform channel — that needs a binding even though
  // nothing here records anything.
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late RemoteControlServer server;
  late int port;

  setUp(() async {
    // The test binding stubs HttpClient out to return an empty 400 — this
    // suite needs to make real calls against the real server.
    HttpOverrides.global = null;
    // Stop/blackout construct the beat detector, whose AudioRecorder calls
    // into the record plugin. There's no plugin host in a unit test, so
    // answer its channel with nothing rather than letting it throw.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (call) async => null,
    );
    container = ProviderContainer();
    container.read(banksProvider.notifier).loadAll([
      Bank(id: 'b1', name: 'Front Wash', sceneSlots: List.filled(4, null)),
    ]);
    container.read(chasesProvider.notifier).loadAll([
      const Chase(id: 'c1', name: 'Rainbow Sweep', steps: []),
    ]);
    server = RemoteControlServer(container.read);
    // Port 0 lets the OS pick a free one, so the test never clashes.
    expect(await server.start(0), isTrue, reason: server.lastError);
    port = server.port!;
  });

  tearDown(() async {
    await server.stop();
    container.dispose();
  });

  Future<Map<String, dynamic>> get(String path) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  test('/status lists every name a macro can fire', () async {
    final body = await get('/status');
    final names = [for (final t in body['targets'] as List) (t as Map)['name']];
    expect(names, containsAll(['Front Wash', 'Rainbow Sweep']));
    expect(body['nowPlaying'], isNull);
  });

  test('/trigger matches the tile name regardless of case', () async {
    final body = await get('/trigger?name=front%20wash');
    // No Art-Net node in a test, so it stops at the connection check — which
    // still proves the name was found and routed to the right action.
    expect(body['message'], isNot(contains('Nothing called')));
  });

  test('/trigger reports an unknown name instead of firing something else', () async {
    final body = await get('/trigger?name=Nope');
    expect(body['message'], contains('Nothing called'));
  });

  test('/stop and /blackout answer', () async {
    expect((await get('/stop'))['ok'], isTrue);
    expect((await get('/blackout'))['ok'], isTrue);
  });

  test('/endpoints serves the watch menu in HttpClient-WearOS format', () async {
    // Pin one of each to the Dashboard — the watch mirrors those, not the
    // whole project.
    container.read(dashboardTriggersProvider.notifier).add('b1', TriggerKind.bank);
    container.read(smartProgramsProvider.notifier).loadAll(const [
      SmartProgram(id: 'p1', name: 'Első okos program'),
    ]);

    final client = HttpClient();
    late String body;
    late String? contentType;
    try {
      final response = await (await client.getUrl(Uri.parse('http://127.0.0.1:$port/endpoints'))).close();
      contentType = response.headers.contentType?.mimeType;
      body = await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }

    // The app refuses anything that isn't text/plain.
    expect(contentType, 'text/plain');
    final lines = body.split('\n');
    expect(lines, contains('- trg,Triggers'));
    expect(lines, contains('- smt,Smart'));
    expect(lines, contains('-- stop,Stop,/stop'));
    expect(lines, contains('-- blk,Blackout,/blackout'));
    // Leaf lines are `<dashes> <id>,<name>,<path>` and the name is encoded
    // into the URL so spaces and accents survive the round trip.
    expect(body, contains(',Front Wash,/trigger?name=Front%20Wash'));
    expect(body, contains('Els%C5%91%20okos%20program'));
    // A chase that isn't pinned to the Dashboard stays off the watch.
    expect(body, isNot(contains('Rainbow Sweep')));
  });

  test('an unknown endpoint says so rather than failing silently', () async {
    final body = await get('/nope');
    expect(body['ok'], isFalse);
    expect(body['message'], contains('Unknown endpoint'));
  });
}
