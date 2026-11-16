import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:yourssh/mobile/files/app_paths.dart';
import 'package:yourssh/mobile/files/file_export.dart';

class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePaths(this.docs, this.support);
  final String docs;
  final String support;
  @override
  Future<String?> getApplicationDocumentsPath() async => docs;
  @override
  Future<String?> getApplicationSupportPath() async => support;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, docs, support;

  setUp(() {
    root = Directory.systemTemp.createTempSync('app_paths_test');
    docs = Directory(p.join(root.path, 'Documents'))..createSync();
    support = Directory(p.join(root.path, 'Support'))..createSync();
    PathProviderPlatform.instance = _FakePaths(docs.path, support.path);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('keys live outside Documents; downloads inside it', () async {
    final keys = await AppPaths.privateKeysDir(
        chmod: (_, _) async {}, excludeFromBackup: (_) async {});
    expect(p.isWithin(docs.path, keys.path), isFalse);
    expect(keys.path, p.join(support.path, 'keys'));
    expect(keys.existsSync(), isTrue);
    final dl = await AppPaths.downloadsDir();
    expect(dl.path, p.join(docs.path, 'Downloads'));
    expect(dl.existsSync(), isTrue);
  });

  test('the key directory is 0700 and excluded from backup', () async {
    final modes = <String, int>{};
    final excluded = <String>[];
    final keys = await AppPaths.privateKeysDir(
      chmod: (path, mode) async => modes[path] = mode,
      excludeFromBackup: (path) async => excluded.add(path),
    );
    expect(modes[keys.path], 0x1C0);
    expect(excluded, [keys.path]);
  });

  test('importPrivateKey copies with 0600 and never overwrites', () async {
    final picked = File(p.join(root.path, 'id_ed25519'))
      ..writeAsStringSync('PRIVATE');
    final into = Directory(p.join(root.path, 'keys'))..createSync();
    final modes = <String, int>{};
    Future<void> chmod(String path, int mode) async => modes[path] = mode;

    final a = await importPrivateKey(picked.path, into, chmod: chmod);
    final b = await importPrivateKey(picked.path, into, chmod: chmod);

    expect(picked.existsSync(), isTrue, reason: 'picked file is copied, not moved');
    expect(p.basename(a.path), 'id_ed25519');
    expect(p.basename(b.path), 'id_ed25519 (1)');
    expect(b.readAsStringSync(), 'PRIVATE');
    expect(modes[a.path], 0x180);
    expect(modes[b.path], 0x180);
  });

  test('importPrivateKey sanitizes the file name', () async {
    final picked = File(p.join(root.path, 'my key (copy).pem'))
      ..writeAsStringSync('x');
    final into = Directory(p.join(root.path, 'keys'))..createSync();
    final f = await importPrivateKey(picked.path, into, chmod: (_, _) async {});
    expect(p.dirname(f.path), into.path);
    expect(p.basename(f.path), isNot(contains(' ')));
  });
}
