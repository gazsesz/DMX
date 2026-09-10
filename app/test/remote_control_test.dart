import 'dart:convert';
import 'dart:io';

import 'package:dmx_controller/core/remote/remote_control_server.dart';
import 'package:dmx_controller/models/bank.dart';
import 'package:dmx_controller/models/chase.dart';
import 'package:dmx_controller/state/bank_providers.dart';
import 'package:dmx_controller/state/chase_providers.dart';
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

  test('an unknown endpoint says so rather than failing silently', () async {
    final body = await get('/nope');
    expect(body['ok'], isFalse);
    expect(body['message'], contains('Unknown endpoint'));
  });
}
