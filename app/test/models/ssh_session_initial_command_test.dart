import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';

void main() {
  test('SshSession stores an optional initialCommand', () {
    final host = Host(label: 'test', host: '1.2.3.4', port: 22, username: 'root');
    final s = SshSession(host: host, initialCommand: 'docker exec -it abc sh');
    expect(s.initialCommand, 'docker exec -it abc sh');
    expect(SshSession(host: host).initialCommand, isNull);
  });
}
