import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';

void main() {
  group('Host', () {
    test('toJson/fromJson round-trips all fields', () {
      final h = Host(
        label: 'Test Server',
        host: '192.168.1.100',
        port: 2222,
        username: 'admin',
        authType: AuthType.password,
      );
      final decoded = Host.fromJson(h.toJson());
      expect(decoded.id, h.id);
      expect(decoded.label, 'Test Server');
      expect(decoded.host, '192.168.1.100');
      expect(decoded.port, 2222);
      expect(decoded.username, 'admin');
      expect(decoded.authType, AuthType.password);
    });

    test('certificate AuthType round-trips through JSON', () {
      final h = Host(
        label: 'Test',
        host: '1.2.3.4',
        username: 'user',
        authType: AuthType.certificate,
        keyId: 'key-1',
      );
      final decoded = Host.fromJson(h.toJson());
      expect(decoded.authType, AuthType.certificate);
      expect(decoded.keyId, 'key-1');
    });

    test('unknown authType throws ArgumentError', () {
      final json = {
        'id': 'x',
        'label': 'x',
        'host': 'x',
        'port': 22,
        'username': 'x',
        'authType': 'nonexistent',
        'group': '',
        'tags': [],
        'createdAt': DateTime.now().toIso8601String(),
      };
      // byName throws ArgumentError on unknown values
      expect(() => Host.fromJson(json), throwsArgumentError);
    });

    test('jumpHostIds round-trips through JSON', () {
      final h = Host(
        label: 'Target',
        host: '10.0.0.5',
        username: 'admin',
        jumpHostIds: ['b1', 'b2'],
      );
      final decoded = Host.fromJson(h.toJson());
      expect(decoded.jumpHostIds, ['b1', 'b2']);
      expect(decoded.jumpHostId, 'b1'); // getter = first hop
    });

    test('toJson dual-writes jumpHostId (first hop) for old apps', () {
      final json =
          Host(label: 'x', host: 'y', username: 'z', jumpHostIds: ['b1', 'b2'])
              .toJson();
      expect(json['jumpHostIds'], ['b1', 'b2']);
      expect(json['jumpHostId'], 'b1');
    });

    test('legacy jumpHostId payload migrates to a one-element list', () {
      final decoded = Host.fromJson({
        'host': 'y',
        'username': 'z',
        'jumpHostId': 'old-bastion',
      });
      expect(decoded.jumpHostIds, ['old-bastion']);
    });

    test('jumpHostIds defaults to empty; jumpHostId getter null', () {
      final h = Host(label: 'x', host: 'y', username: 'z');
      expect(h.jumpHostIds, isEmpty);
      expect(h.jumpHostId, isNull);
      expect(Host.fromJson(h.toJson()).jumpHostIds, isEmpty);
    });

    test('malformed jumpHostIds degrades to empty', () {
      final decoded = Host.fromJson(
          {'host': 'y', 'username': 'z', 'jumpHostIds': 'garbage'});
      expect(decoded.jumpHostIds, isEmpty);
    });

    test('copyWith preserves jumpHostIds when not overridden', () {
      final h =
          Host(label: 'x', host: 'y', username: 'z', jumpHostIds: ['jid']);
      expect(h.copyWith(label: 'new').jumpHostIds, ['jid']);
    });

    test('copyWith clears jumpHostIds with an empty list', () {
      final h =
          Host(label: 'x', host: 'y', username: 'z', jumpHostIds: ['jid']);
      expect(h.copyWith(jumpHostIds: const []).jumpHostIds, isEmpty);
    });

    test('jumpHostIds is an owned growable copy', () {
      final h = Host(
          label: 'x', host: 'y', username: 'z', jumpHostIds: const ['a']);
      expect(() => h.jumpHostIds.add('b'), returnsNormally);
    });

    test('recordingRedaction round-trips and defaults to true', () {
      final h = Host(label: 'x', host: 'y', username: 'z');
      expect(h.recordingRedaction, isTrue);
      expect(Host.fromJson(h.toJson()).recordingRedaction, isTrue);

      final off = Host(
          label: 'x', host: 'y', username: 'z', recordingRedaction: false);
      expect(Host.fromJson(off.toJson()).recordingRedaction, isFalse);
    });

    test('recordingRedaction missing in JSON defaults to true', () {
      final decoded = Host.fromJson({'host': 'y', 'username': 'z'});
      expect(decoded.recordingRedaction, isTrue);
    });

    test('copyWith keeps and overrides recordingRedaction', () {
      final h = Host(
          label: 'x', host: 'y', username: 'z', recordingRedaction: false);
      expect(h.copyWith(label: 'new').recordingRedaction, isFalse);
      expect(h.copyWith(recordingRedaction: true).recordingRedaction, isTrue);
    });
  });
}
