import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/container_entry.dart';

import 'package:yourssh/services/container_service.dart';

import 'fake_ssh_for_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final host = Host(label: 'h', host: 'srv', port: 22, username: 'u');
  const evil = "x'; touch /tmp/pwn; echo '";
  const quoted = r"'x'\''; touch /tmp/pwn; echo '\'''";

  test('listPods quotes namespace and context', () async {
    final ssh = RecordingSsh();
    await ContainerService(ssh)
        .listPods(host, namespace: evil, context: evil)
        .catchError((_) => <PodEntry>[]);
    expect(ssh.execCmds.single, contains('-n $quoted'));
    expect(ssh.execCmds.single, contains('--context=$quoted'));
  });

  test('podContainers quotes pod and namespace', () async {
    final ssh = RecordingSsh();
    await ContainerService(ssh).podContainers(host, evil, evil);
    expect(ssh.execCmds.single, contains('get pod $quoted -n $quoted'));
  });

  test('streamLogs quotes pod, namespace, context and container', () {
    final ssh = RecordingSsh();
    ContainerService(ssh)
        .streamLogs(host, evil, evil, evil, container: evil);
    final cmd = ssh.streamCmds.single;
    expect(cmd, contains('logs -f $quoted -n $quoted'));
    expect(cmd, contains('--context=$quoted'));
    expect(cmd, contains('-c $quoted'));
  });

  test('startPodPortForward quotes args and binds 127.0.0.1', () async {
    final ssh = RecordingSsh();
    try {
      await ContainerService(ssh)
          .startPodPortForward(host, evil, evil, evil, 80, 8080);
    } catch (_) {}
    final cmd = ssh.streamCmds.single;
    expect(cmd, contains('--address 127.0.0.1'));
    expect(cmd, isNot(contains('0.0.0.0')));
    expect(cmd, contains('pod/$quoted'));
    expect(cmd, contains('-n $quoted'));
    expect(cmd, contains('--context=$quoted'));
  });

  test('kubectlExecCommand quotes pod, namespace and container', () {
    final cmd = ContainerService.kubectlExecCommand(evil, evil, evil);
    expect(cmd, contains('kubectl exec -it $quoted -n $quoted -c $quoted --'));
  });
}
