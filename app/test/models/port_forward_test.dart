import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/port_forward.dart';

void main() {
  test('autoStart round-trips through JSON and defaults to false', () {
    final fwd = PortForward(
      label: 'db',
      type: ForwardType.local,
      localPort: 8080,
      remoteHost: 'db',
      remotePort: 5432,
      autoStart: true,
    );
    final restored = PortForward.fromJson(fwd.toJson());
    expect(restored.autoStart, isTrue);

    final legacy = PortForward.fromJson({
      'id': 'x',
      'label': 'old',
      'type': 'local',
      'localPort': 80,
    });
    expect(legacy.autoStart, isFalse);
  });

  test('status, errorMessage and activeConnections are transient', () {
    final fwd =
        PortForward(label: 'a', type: ForwardType.dynamic, localPort: 1080)
          ..status = ForwardStatus.active
          ..errorMessage = 'boom'
          ..activeConnections = 3;
    final json = fwd.toJson();
    expect(json.containsKey('status'), isFalse);
    expect(json.containsKey('errorMessage'), isFalse);
    expect(json.containsKey('activeConnections'), isFalse);
    final restored = PortForward.fromJson(json);
    expect(restored.status, ForwardStatus.idle);
    expect(restored.activeConnections, 0);
  });

  test('ForwardStatus has connecting and reconnecting states', () {
    expect(
        ForwardStatus.values,
        containsAll([
          ForwardStatus.idle,
          ForwardStatus.connecting,
          ForwardStatus.active,
          ForwardStatus.reconnecting,
          ForwardStatus.error,
        ]));
  });
}
