import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/services/sandbox_migration.dart';

void main() {
  group('parseXmlPlist', () {
    test('reads the value types shared_preferences emits', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>flutter.yourssh.hosts</key>
	<string>[{"id":"a"}]</string>
	<key>flutter.autoReconnect</key>
	<true/>
	<key>flutter.tmuxEnabled</key>
	<false/>
	<key>flutter.fontSize</key>
	<real>13.5</real>
	<key>flutter.auditRetentionDays</key>
	<integer>90</integer>
	<key>flutter.hotkeys</key>
	<array>
		<string>new_session</string>
		<string>close_session</string>
	</array>
</dict>
</plist>
''';
      final plist = parseXmlPlist(xml);
      expect(plist['flutter.yourssh.hosts'], '[{"id":"a"}]');
      expect(plist['flutter.autoReconnect'], isTrue);
      expect(plist['flutter.tmuxEnabled'], isFalse);
      expect(plist['flutter.fontSize'], 13.5);
      expect(plist['flutter.auditRetentionDays'], 90);
      expect(plist['flutter.hotkeys'], ['new_session', 'close_session']);
    });

    test('unescapes XML entities in string values', () {
      const xml = '''
<plist version="1.0"><dict>
<key>flutter.snippet</key><string>echo &quot;a &amp; b&quot; &lt;&gt; &apos;c&apos;</string>
</dict></plist>
''';
      expect(parseXmlPlist(xml)['flutter.snippet'], 'echo "a & b" <> \'c\'');
    });

    test('skips container-only keys with unsupported value types', () {
      const xml = '''
<plist version="1.0"><dict>
<key>NSOSPLastRootDirectory</key><data>Zm9v</data>
<key>NSNavPanelExpandedSizeForOpenMode</key>
<dict><key>width</key><integer>712</integer></dict>
<key>flutter.autoReconnect</key><true/>
</dict></plist>
''';
      final plist = parseXmlPlist(xml);
      expect(plist.containsKey('NSOSPLastRootDirectory'), isFalse);
      expect(plist.containsKey('NSNavPanelExpandedSizeForOpenMode'), isFalse);
      expect(plist['flutter.autoReconnect'], isTrue);
    });

    test('returns empty map for junk input', () {
      expect(parseXmlPlist(''), isEmpty);
      expect(parseXmlPlist('not a plist'), isEmpty);
    });
  });

  group('planPrefsMigration', () {
    test('strips the flutter. prefix and drops non-prefs keys', () {
      final plan = planPrefsMigration(
        {
          'flutter.yourssh.hosts': '[]',
          'flutter.autoReconnect': true,
          'NSWindowFrame': 'ignored',
        },
        existingKeys: const {},
      );
      expect(plan.keys, containsAll(['yourssh.hosts', 'autoReconnect']));
      expect(plan.containsKey('NSWindowFrame'), isFalse);
    });

    test('never overwrites a key the unsandboxed domain already has', () {
      final plan = planPrefsMigration(
        {'flutter.autoReconnect': true, 'flutter.tmuxEnabled': true},
        existingKeys: const {'autoReconnect'},
      );
      expect(plan.keys, ['tmuxEnabled']);
    });
  });

  group('SandboxMigrationService.run', () {
    late Directory tmp;
    late Directory home;
    late Directory container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = await Directory.systemTemp.createTemp('ys_sandbox_mig');
      home = Directory(p.join(tmp.path, 'home'))..createSync(recursive: true);
      container = Directory(
        p.join(home.path, 'Library', 'Containers', 'com.thangnm.yourssh', 'Data'),
      )..createSync(recursive: true);
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    SandboxMigrationService service({String? plistXml}) =>
        SandboxMigrationService(
          homeRoot: home.path,
          bundleId: 'com.thangnm.yourssh',
          readPlist: (path) async => plistXml,
        );

    void writeContainerFile(String relative, String content) {
      final file = File(p.join(container.path, relative));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    test('copies prefs, audit database and JS plugins out of the container',
        () async {
      writeContainerFile(
          'Library/Application Support/com.thangnm.yourssh/audit.db', 'sqlite');
      writeContainerFile('.yourssh/plugins/mine/plugin.json', '{"id":"mine"}');
      final prefs = await SharedPreferences.getInstance();

      final result = await service(plistXml: '''
<plist version="1.0"><dict>
<key>flutter.yourssh.hosts</key><string>[{"id":"a"}]</string>
<key>flutter.autoReconnect</key><false/>
<key>flutter.fontSize</key><real>15</real>
<key>flutter.auditRetentionDays</key><integer>30</integer>
<key>flutter.hotkeys</key><array><string>a</string></array>
</dict></plist>
''').run(prefs);

      expect(result.migrated, isTrue);
      expect(result.prefKeys, 5);
      expect(prefs.getString('yourssh.hosts'), '[{"id":"a"}]');
      expect(prefs.getBool('autoReconnect'), isFalse);
      expect(prefs.getDouble('fontSize'), 15);
      expect(prefs.getInt('auditRetentionDays'), 30);
      expect(prefs.getStringList('hotkeys'), ['a']);
      expect(
        File(p.join(home.path, 'Library', 'Application Support',
                'com.thangnm.yourssh', 'audit.db'))
            .existsSync(),
        isTrue,
      );
      expect(
        File(p.join(home.path, '.yourssh', 'plugins', 'mine', 'plugin.json'))
            .existsSync(),
        isTrue,
      );
      expect(prefs.getBool(SandboxMigrationService.markerKey), isTrue);
    });

    test('runs once — a second call is a no-op', () async {
      final prefs = await SharedPreferences.getInstance();
      final first = await service(plistXml: '''
<plist version="1.0"><dict><key>flutter.autoReconnect</key><false/></dict></plist>
''').run(prefs);
      expect(first.migrated, isTrue);

      await prefs.setBool('autoReconnect', true);
      final second = await service(plistXml: '''
<plist version="1.0"><dict><key>flutter.autoReconnect</key><false/></dict></plist>
''').run(prefs);

      expect(second.migrated, isFalse);
      expect(prefs.getBool('autoReconnect'), isTrue, reason: 'must not clobber');
    });

    test('never overwrites files that already exist outside the container',
        () async {
      writeContainerFile(
          'Library/Application Support/com.thangnm.yourssh/audit.db', 'old');
      final target = File(p.join(home.path, 'Library', 'Application Support',
          'com.thangnm.yourssh', 'audit.db'));
      target.parent.createSync(recursive: true);
      target.writeAsStringSync('current');

      await service(plistXml: '<plist version="1.0"><dict/></plist>')
          .run(await SharedPreferences.getInstance());

      expect(target.readAsStringSync(), 'current');
    });

    test('marks itself done when there is no container to migrate', () async {
      container.deleteSync(recursive: true);
      final prefs = await SharedPreferences.getInstance();

      final result = await service().run(prefs);

      expect(result.migrated, isFalse);
      expect(result.reason, 'no-container');
      expect(prefs.getBool(SandboxMigrationService.markerKey), isTrue);
    });

    test('reads a real binary plist through plutil', () async {
      // The default reader shells out to plutil — the container's plist is
      // binary, which no Dart plist parser in this app can read directly.
      final xmlSource = File(p.join(tmp.path, 'src.plist'))
        ..writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>flutter.yourssh.hosts</key><string>[{"id":"real"}]</string>
<key>flutter.fontSize</key><real>14</real>
</dict></plist>
''');
      final target = File(p.join(
          container.path, 'Library', 'Preferences', 'com.thangnm.yourssh.plist'));
      target.parent.createSync(recursive: true);
      xmlSource.copySync(target.path);
      final converted = await Process.run(
          'plutil', ['-convert', 'binary1', target.path]);
      expect(converted.exitCode, 0, reason: 'plutil must produce a binary plist');
      final prefs = await SharedPreferences.getInstance();

      final result = await SandboxMigrationService(
        homeRoot: home.path,
        bundleId: 'com.thangnm.yourssh',
      ).run(prefs);

      expect(result.prefKeys, 2);
      expect(prefs.getString('yourssh.hosts'), '[{"id":"real"}]');
      expect(prefs.getDouble('fontSize'), 14);
    }, skip: !Platform.isMacOS ? 'plutil is macOS-only' : null);

    test('still migrates files when the container prefs plist is unreadable',
        () async {
      writeContainerFile('.yourssh/plugins/mine/plugin.json', '{}');
      final prefs = await SharedPreferences.getInstance();

      final result = await service(plistXml: null).run(prefs);

      expect(result.prefKeys, 0);
      expect(
        File(p.join(home.path, '.yourssh', 'plugins', 'mine', 'plugin.json'))
            .existsSync(),
        isTrue,
      );
      expect(prefs.getBool(SandboxMigrationService.markerKey), isTrue);
    });
  });
}
