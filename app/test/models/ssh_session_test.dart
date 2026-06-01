import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';

Host _host() => Host(id: 'h1', label: 'prod', host: 'prod.example.com', port: 22, username: 'alice');

void main() {
  group('SshSession tab metadata fields', () {
    test('defaults: customLabel null, colorTag null, isPinned false', () {
      final s = SshSession(host: _host());
      expect(s.customLabel, isNull);
      expect(s.colorTag, isNull);
      expect(s.isPinned, isFalse);
    });

    test('title returns customLabel when set', () {
      final s = SshSession(host: _host());
      s.customLabel = 'my-prod';
      expect(s.title, 'my-prod');
    });

    test('title falls back to user@host when customLabel is null', () {
      final s = SshSession(host: _host());
      expect(s.title, 'alice@prod.example.com');
    });

    test('title falls back to user@host when customLabel is cleared to null', () {
      final s = SshSession(host: _host());
      s.customLabel = 'custom';
      s.customLabel = null;
      expect(s.title, 'alice@prod.example.com');
    });

    test('colorTag can be set and cleared', () {
      final s = SshSession(host: _host());
      s.colorTag = '#ef4444';
      expect(s.colorTag, '#ef4444');
      s.colorTag = null;
      expect(s.colorTag, isNull);
    });

    test('isPinned can be toggled', () {
      final s = SshSession(host: _host());
      s.isPinned = true;
      expect(s.isPinned, isTrue);
      s.isPinned = false;
      expect(s.isPinned, isFalse);
    });

    test('watch session title is not affected by customLabel logic', () {
      final s = SshSession.watch(watchedTitle: 'alice@prod.example.com');
      expect(s.title, '[WATCH] alice@prod.example.com');
      s.customLabel = 'renamed';
      expect(s.title, 'renamed');
    });

    test('tabLabel falls back to host.label, not user@host', () {
      final s = SshSession(host: _host());
      expect(s.tabLabel, 'prod'); // host.label, not 'alice@prod.example.com'
    });

    test('tabLabel returns customLabel when set', () {
      final s = SshSession(host: _host());
      s.customLabel = 'my-tab';
      expect(s.tabLabel, 'my-tab');
    });
  });
}
