import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/panel_source.dart';

Host _host({String label = 'srv'}) => Host(
      label: label,
      host: '10.0.0.1',
      username: 'root',
      authType: AuthType.password,
    );

void main() {
  group('PanelSource equality', () {
    test('LocalSource instances are equal', () {
      expect(const LocalSource(), const LocalSource());
    });

    test('HostSource equality follows host id', () {
      final h = _host();
      expect(HostSource(h), HostSource(h));
      expect(HostSource(h) == HostSource(_host()), isFalse); // different id
      expect(HostSource(h) == const LocalSource(), isFalse);
    });
  });

  group('transferKindFor', () {
    final remote = HostSource(_host());
    final remote2 = HostSource(_host(label: 'other'));
    const local = LocalSource();

    test('local → local is a filesystem copy', () {
      expect(transferKindFor(local, local), TransferKind.localCopy);
    });

    test('local → remote is an upload', () {
      expect(transferKindFor(local, remote), TransferKind.upload);
    });

    test('remote → local is a download', () {
      expect(transferKindFor(remote, local), TransferKind.download);
    });

    test('remote → remote relays through a temp file (even same host)', () {
      expect(transferKindFor(remote, remote2), TransferKind.remoteRelay);
      expect(transferKindFor(remote, remote), TransferKind.remoteRelay);
    });
  });
}
