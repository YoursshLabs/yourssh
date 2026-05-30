import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';

void main() {
  group('Host.detectedOs', () {
    test('toJson includes detectedOs when set', () {
      final host = Host(
        id: 'h1', label: 'box', host: '1.2.3.4', port: 22, username: 'u',
        detectedOs: 'linux',
      );
      expect(host.toJson()['detectedOs'], 'linux');
    });

    test('toJson includes null detectedOs when unset', () {
      final host = Host(id: 'h1', label: 'box', host: '1.2.3.4', port: 22, username: 'u');
      expect(host.toJson()['detectedOs'], isNull);
    });

    test('fromJson restores detectedOs', () {
      final json = {
        'id': 'h1', 'label': 'box', 'host': '1.2.3.4', 'port': 22,
        'username': 'u', 'authType': 'password', 'group': '',
        'tags': <String>[], 'createdAt': '2026-01-01T00:00:00.000Z',
        'detectedOs': 'macos',
      };
      expect(Host.fromJson(json).detectedOs, 'macos');
    });

    test('fromJson defaults detectedOs to null when key absent', () {
      final json = {
        'id': 'h1', 'label': 'box', 'host': '1.2.3.4', 'port': 22,
        'username': 'u', 'authType': 'password', 'group': '',
        'tags': <String>[], 'createdAt': '2026-01-01T00:00:00.000Z',
      };
      expect(Host.fromJson(json).detectedOs, isNull);
    });

    test('copyWith preserves detectedOs when not overridden', () {
      final host = Host(
        id: 'h1', label: 'box', host: '1.2.3.4', port: 22, username: 'u',
        detectedOs: 'windows',
      );
      expect(host.copyWith(label: 'new').detectedOs, 'windows');
    });

    test('copyWith can update detectedOs', () {
      final host = Host(
        id: 'h1', label: 'box', host: '1.2.3.4', port: 22, username: 'u',
        detectedOs: 'linux',
      );
      expect(host.copyWith(detectedOs: 'macos').detectedOs, 'macos');
    });
  });
}
