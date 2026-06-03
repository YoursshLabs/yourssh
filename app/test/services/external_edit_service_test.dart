// app/test/services/external_edit_service_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/sftp_entry.dart';
import 'package:yourssh/services/external_edit_service.dart';
import 'package:yourssh/services/sftp_transfer_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';

class FakeTransferService extends SftpTransferService {
  FakeTransferService() : super(SshService(StorageService()));

  final uploads = <(String, String)>[]; // (localPath, remotePath)
  Object? uploadError;

  @override
  Future<String?> downloadToTemp(Host host, SftpEntry entry) async {
    final dir = await Directory.systemTemp.createTemp('yourssh_ext_test');
    final file = File('${dir.path}/${entry.name}');
    await file.writeAsString('remote content');
    return file.path;
  }

  @override
  Future<void> uploadFile(
      Host host, String localPath, String remotePath) async {
    final err = uploadError;
    if (err != null) throw err;
    uploads.add((localPath, remotePath));
  }
}

final _host = Host(label: 'h', host: 'example.com', username: 'u');
final _entry = SftpEntry(
  name: 'data.bin',
  path: '/srv/data.bin',
  isDirectory: false,
  size: 14,
  modifiedAt: DateTime(2026),
);

/// Polls [condition] until true or fails after 5 s (real timers — the
/// service does real file IO, so fakeAsync is not an option).
Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not met within 5s');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late FakeTransferService transfer;
  late ExternalEditService service;
  late List<Uri> launched;

  setUp(() {
    transfer = FakeTransferService();
    launched = [];
    service = ExternalEditService(
      transfer,
      launcher: (uri) async {
        launched.add(uri);
        return true;
      },
      pollInterval: const Duration(milliseconds: 30),
    );
  });

  tearDown(() => service.dispose());

  test('openExternal downloads the file and launches the local copy',
      () async {
    await service.openExternal(_host, _entry);

    expect(launched, hasLength(1));
    expect(launched.first.isScheme('file'), isTrue);
    expect(File.fromUri(launched.first).readAsStringSync(), 'remote content');
    expect(service.activeWatchCount, 1);
  });

  test('modifying the local copy uploads it back to the server', () async {
    await service.openExternal(_host, _entry);
    final local = File.fromUri(launched.first);
    final uploadedNames = <String>[];
    service.onUploaded = uploadedNames.add;

    await local.writeAsString('edited');
    local.setLastModifiedSync(DateTime.now().add(const Duration(seconds: 2)));

    await _waitFor(() => transfer.uploads.isNotEmpty);
    expect(transfer.uploads.single.$2, '/srv/data.bin');
    expect(uploadedNames, ['data.bin']);
  });

  test('upload failure reports the error and keeps watching', () async {
    await service.openExternal(_host, _entry);
    final local = File.fromUri(launched.first);
    final errors = <String>[];
    service.onUploadError = (name, _) => errors.add(name);

    transfer.uploadError = Exception('network down');
    local.setLastModifiedSync(DateTime.now().add(const Duration(seconds: 2)));
    await _waitFor(() => errors.isNotEmpty);
    expect(transfer.uploads, isEmpty);

    // Next save after the error must still upload.
    transfer.uploadError = null;
    local.setLastModifiedSync(DateTime.now().add(const Duration(seconds: 4)));
    await _waitFor(() => transfer.uploads.isNotEmpty);
  });

  test('launch failure throws and does not start a watcher', () async {
    final failing = ExternalEditService(
      transfer,
      launcher: (_) async => false,
      pollInterval: const Duration(milliseconds: 30),
    );
    await expectLater(failing.openExternal(_host, _entry),
        throwsA(isA<ExternalEditException>()));
    expect(failing.activeWatchCount, 0);
  });

  test('dispose cancels all watchers', () async {
    await service.openExternal(_host, _entry);
    service.dispose();
    expect(service.activeWatchCount, 0);
  });
}
