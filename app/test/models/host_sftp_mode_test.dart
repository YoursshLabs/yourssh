import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';

void main() {
  Host base() => Host(label: 'srv', host: '1.2.3.4', username: 'u');

  group('Host.sftpMode', () {
    test('defaults to normal', () {
      expect(base().sftpMode, SftpMode.normal);
      expect(base().sftpServerCommand, isNull);
    });

    test('round-trips through JSON', () {
      final host = Host(
        label: 'srv',
        host: '1.2.3.4',
        username: 'u',
        sftpMode: SftpMode.custom,
        sftpServerCommand: 'sudo /usr/lib/openssh/sftp-server',
      );
      final restored = Host.fromJson(host.toJson());
      expect(restored.sftpMode, SftpMode.custom);
      expect(restored.sftpServerCommand, 'sudo /usr/lib/openssh/sftp-server');
    });

    test('absent JSON keys parse as normal (backward compat)', () {
      final json = base().toJson()
        ..remove('sftpMode')
        ..remove('sftpServerCommand');
      final restored = Host.fromJson(json);
      expect(restored.sftpMode, SftpMode.normal);
      expect(restored.sftpServerCommand, isNull);
    });

    test('unknown forward-compat sftpMode degrades to normal, never throws', () {
      final json = base().toJson()..['sftpMode'] = 'futuremode';
      final restored = Host.fromJson(json);
      expect(restored.sftpMode, SftpMode.normal);
    });

    test('copyWith updates and clears sftp fields', () {
      final host = base().copyWith(
        sftpMode: SftpMode.sudo,
        sftpServerCommand: 'x',
      );
      expect(host.sftpMode, SftpMode.sudo);
      expect(host.sftpServerCommand, 'x');
      // Omitting keeps values; explicit null clears the command.
      expect(host.copyWith().sftpServerCommand, 'x');
      expect(host.copyWith(sftpServerCommand: null).sftpServerCommand, isNull);
    });
  });
}
