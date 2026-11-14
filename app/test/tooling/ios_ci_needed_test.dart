import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Future<String> needed(List<String> files) async {
  final p = await Process.start('bash', ['../tool/ios_ci_needed.sh']);
  p.stdin.write(files.map((f) => '$f\n').join());
  await p.stdin.close();
  final out = await p.stdout.transform(const SystemEncoding().decoder).join();
  expect(await p.exitCode, 0);
  return out.trim();
}

void main() {
  test('docs-only changes skip the iOS job', () async {
    expect(
      await needed([
        'README.md',
        'CHANGELOG.md',
        'docs/superpowers/specs/x-design.md',
        'screenshots/docs/01.png',
        '.claude/skills/yourssh-docs-sync/SKILL.md',
      ]),
      'false',
    );
  });

  test('any app, package, tool or workflow change runs the iOS job', () async {
    for (final f in [
      'app/lib/main.dart',
      'app/ios/Runner/Info.plist',
      'packages/dartssh2/lib/src/ssh_client.dart',
      'tool/check_ios_bundle.sh',
      '.github/workflows/pr-test.yml',
      'app/pubspec.yaml',
    ]) {
      expect(await needed(['README.md', f]), 'true', reason: f);
    }
  });

  test('an empty or unknown change list runs the iOS job', () async {
    expect(await needed([]), 'true');
  });

  test('pr-test.yml gates the ios job on the changes job and accepts a skip',
      () {
    final y = File('../.github/workflows/pr-test.yml').readAsStringSync();
    expect(y, contains('tool/ios_ci_needed.sh'));
    expect(y, contains("if: needs.changes.outputs.ios == 'true'"));
    expect(y, contains('needs: [app, ui, bridge, android, cli, windows-cli, ios, changes]'));
    expect(y, contains('needs.ios.result }}" = "skipped"'));
  });
}
