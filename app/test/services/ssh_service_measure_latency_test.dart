// app/test/services/ssh_service_measure_latency_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';

void main() {
  test('measureLatency returns null for an unknown host', () async {
    final ssh = SshService(StorageService());
    expect(await ssh.measureLatency('no-such-host'), isNull);
  });

  test('connectedHostIds is empty before any connect', () {
    final ssh = SshService(StorageService());
    expect(ssh.connectedHostIds, isEmpty);
  });
}
