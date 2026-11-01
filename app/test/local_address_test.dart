import 'package:dmx_controller/core/network/local_address.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pickLocalAddress', () {
    test('prefers the Wi-Fi interface over mobile data listed first', () {
      expect(
        pickLocalAddress([
          (name: 'rmnet_data0', ipv4: ['10.42.7.1']),
          (name: 'wlan0', ipv4: ['192.168.1.23']),
        ]),
        '192.168.1.23',
      );
    });

    test('skips link-local addresses', () {
      expect(
        pickLocalAddress([
          (name: 'wlan0', ipv4: ['169.254.3.4']),
          (name: 'eth0', ipv4: ['10.0.0.5']),
        ]),
        '10.0.0.5',
      );
    });

    test('falls back to an unknown name, never to mobile data or a tunnel', () {
      expect(pickLocalAddress([(name: 'ap0', ipv4: ['192.168.43.1'])]), '192.168.43.1');
      expect(
        pickLocalAddress([
          (name: 'rmnet0', ipv4: ['10.1.1.1']),
          (name: 'tun0', ipv4: ['10.8.0.2']),
        ]),
        isNull,
      );
      expect(pickLocalAddress(const []), isNull);
    });
  });

  test('watchLocalAddress reports the first address and then only changes', () {
    fakeAsync((async) {
      final answers = ['192.168.1.23', '192.168.1.23', null, '10.0.0.7', '10.0.0.7'];
      var i = 0;
      final seen = <String?>[];
      final sub = watchLocalAddress(
        every: const Duration(seconds: 3),
        read: () async => answers[i < answers.length - 1 ? i++ : i],
      ).listen(seen.add);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 13));
      expect(seen, ['192.168.1.23', null, '10.0.0.7']);
      sub.cancel();
      async.elapse(const Duration(seconds: 10));
      expect(async.pendingTimers, isEmpty);
    });
  });
}
