import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/port_forward.dart';
import 'package:yourssh/providers/port_forward_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  PortForward rule({String label = 'r'}) => PortForward(
      label: label,
      type: ForwardType.local,
      localPort: 8080,
      remoteHost: 'db',
      remotePort: 5432);

  test('update replaces the rule and persists it', () async {
    final p = PortForwardProvider();
    await p.ready;
    final fwd = rule();
    await p.add(fwd);

    final edited = PortForward(
        id: fwd.id,
        label: 'renamed',
        type: ForwardType.dynamic,
        localPort: 1080,
        autoStart: true);
    await p.update(edited);
    expect(p.forwards.single.label, 'renamed');
    expect(p.forwards.single.autoStart, isTrue);

    final p2 = PortForwardProvider();
    await p2.ready;
    expect(p2.forwards.single.label, 'renamed');
    expect(p2.forwards.single.autoStart, isTrue);
  });

  test('update of unknown id is a no-op', () async {
    final p = PortForwardProvider();
    await p.ready;
    await p.update(rule());
    expect(p.forwards, isEmpty);
  });

  test('setConnections updates transient count, drops silently if deleted',
      () async {
    final p = PortForwardProvider();
    await p.ready;
    final fwd = rule();
    await p.add(fwd);
    p.setConnections(fwd.id, 4);
    expect(p.forwards.single.activeConnections, 4);
    p.setConnections('gone', 9); // must not throw
  });
}
