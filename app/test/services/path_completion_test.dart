import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/path_completion.dart';

void main() {
  group('planPathCompletion', () {
    test('absolute path token -> dir + prefix', () {
      final p = planPathCompletion('cat /etc/ho', '/home/u')!;
      expect(p.dir, '/etc');
      expect(p.prefix, 'ho');
    });
    test('relative token resolves against cwd', () {
      final p = planPathCompletion('cd sub/fo', '/home/u')!;
      expect(p.dir, '/home/u/sub');
      expect(p.prefix, 'fo');
    });
    test('bare path-command + no slash lists cwd', () {
      final p = planPathCompletion('cd ', '/home/u')!;
      expect(p.dir, '/home/u');
      expect(p.prefix, '');
    });
    test('non-path command without slash -> null', () {
      expect(planPathCompletion('echo hello', '/home/u'), isNull);
    });
    test('relative token but no cwd -> null', () {
      expect(planPathCompletion('cd sub/fo', null), isNull);
    });
    test('still typing the command word -> null', () {
      expect(planPathCompletion('cd', '/home/u'), isNull);
    });
  });

  group('mergePathSuggestions', () {
    test('replaces the path token, filters by prefix, keeps the command', () {
      final out = mergePathSuggestions(
        'cat /etc/ho',
        const PathPlan(dir: '/etc', prefix: 'ho'),
        ['hostname', 'hosts/', 'group'],
      );
      expect(out, ['cat /etc/hostname', 'cat /etc/hosts/']);
    });
    test('no-slash relative token completes against the command head', () {
      final out = mergePathSuggestions(
        'cd do',
        const PathPlan(dir: '/home/u', prefix: 'do'),
        ['documents/', 'downloads/', 'music/'],
      );
      expect(out, ['cd documents/', 'cd downloads/']);
    });
  });
}
