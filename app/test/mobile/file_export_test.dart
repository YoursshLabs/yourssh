import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/files/file_export.dart';
import 'package:yourssh/util/safe_local_path.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('file_export_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('uniqueLocalPath never overwrites and rejects unsafe names', () {
    expect(uniqueLocalPath(tmp.path, 'a.txt'), '${tmp.path}/a.txt');
    File('${tmp.path}/a.txt').createSync();
    expect(uniqueLocalPath(tmp.path, 'a.txt'), '${tmp.path}/a (1).txt');
    File('${tmp.path}/a (1).txt').createSync();
    expect(uniqueLocalPath(tmp.path, 'a.txt'), '${tmp.path}/a (2).txt');
    expect(() => uniqueLocalPath(tmp.path, '../x'),
        throwsA(isA<UnsafeRemotePathException>()));
  });

  test('writeDownload writes via .part and renames on success', () async {
    final out = '${tmp.path}/ok.bin';
    await writeDownload(Stream.fromIterable([
      [1, 2],
      [3],
    ]), out);
    expect(File(out).readAsBytesSync(), [1, 2, 3]);
    expect(File('$out.part').existsSync(), isFalse);
  });

  test('writeDownload leaves nothing behind when the stream fails', () async {
    final c = StreamController<List<int>>();
    final f = writeDownload(c.stream, '${tmp.path}/out.bin');
    c
      ..add([1, 2])
      ..addError(Exception('connection closed'));
    await expectLater(f, throwsException);
    expect(File('${tmp.path}/out.bin').existsSync(), isFalse);
    expect(File('${tmp.path}/out.bin.part').existsSync(), isFalse);
  });
}
