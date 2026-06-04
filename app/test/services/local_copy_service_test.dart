import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yourssh/services/local_copy_service.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('local_copy_test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<File> makeFile(String relPath, String content) async {
    final f = File(p.join(tmp.path, relPath));
    await f.create(recursive: true);
    await f.writeAsString(content);
    return f;
  }

  test('copies a single file into the destination directory', () async {
    final src = await makeFile('src/a.txt', 'hello');
    final dstDir = await Directory(p.join(tmp.path, 'dst')).create();

    await LocalCopyService().copyEntry(src.path, dstDir.path);

    expect(await File(p.join(dstDir.path, 'a.txt')).readAsString(), 'hello');
  });

  test('copies a directory recursively', () async {
    await makeFile('src/dir/one.txt', '1');
    await makeFile('src/dir/nested/two.txt', '2');
    final dstDir = await Directory(p.join(tmp.path, 'dst')).create();

    await LocalCopyService().copyEntry(p.join(tmp.path, 'src/dir'), dstDir.path);

    expect(await File(p.join(dstDir.path, 'dir/one.txt')).readAsString(), '1');
    expect(
        await File(p.join(dstDir.path, 'dir/nested/two.txt')).readAsString(), '2');
  });

  test('throws when destination equals the source parent directory', () async {
    final src = await makeFile('src/a.txt', 'hello');

    expect(
      () => LocalCopyService().copyEntry(src.path, p.join(tmp.path, 'src')),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('throws when copying a directory into itself', () async {
    await makeFile('src/dir/one.txt', '1');
    final dir = p.join(tmp.path, 'src/dir');

    expect(
      () => LocalCopyService().copyEntry(dir, dir),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('reports per-file progress bytes', () async {
    await makeFile('src/dir/one.txt', '12345');
    await makeFile('src/dir/two.txt', '678');
    final dstDir = await Directory(p.join(tmp.path, 'dst')).create();

    var total = 0;
    await LocalCopyService().copyEntry(
      p.join(tmp.path, 'src/dir'),
      dstDir.path,
      onBytes: (n) => total += n,
    );

    expect(total, 8);
  });
}
