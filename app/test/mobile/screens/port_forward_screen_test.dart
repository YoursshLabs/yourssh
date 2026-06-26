import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yourssh/mobile/screens/mobile_port_forward_screen.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/port_forward.dart';
import 'package:yourssh/providers/port_forward_provider.dart';
import 'package:yourssh/services/port_forward_service.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakePortForwardProvider extends PortForwardProvider {
  final List<PortForward> _fakeForwards;
  _FakePortForwardProvider(this._fakeForwards);

  @override
  List<PortForward> get forwards => List.unmodifiable(_fakeForwards);
}

class _FakePortForwardService extends PortForwardService {
  _FakePortForwardService()
      : super(
          acquireTransport: (_) async => throw UnimplementedError(),
          resolveHost: (_) => null,
          onStatus: (_, __, {error}) {},
          onConnections: (_, __) {},
        );

  final startedIds = <String>[];
  final stoppedIds = <String>[];

  @override
  Future<void> start(PortForward fwd) async => startedIds.add(fwd.id);

  @override
  Future<void> stop(String forwardId) async => stoppedIds.add(forwardId);

  @override
  bool isRunning(String forwardId) => false;
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

final _host = Host(
  id: 'h1',
  label: 'db-prod',
  host: '10.0.0.1',
  port: 22,
  username: 'admin',
);

final _activeRule = PortForward(
  id: 'r1',
  label: 'postgres',
  type: ForwardType.local,
  localHost: '127.0.0.1',
  localPort: 5432,
  remoteHost: 'db-prod',
  remotePort: 5432,
  hostId: 'h1',
  status: ForwardStatus.active,
);

final _stoppedRule = PortForward(
  id: 'r2',
  label: 'socks',
  type: ForwardType.dynamic,
  localHost: '127.0.0.1',
  localPort: 1080,
  hostId: 'h1',
  status: ForwardStatus.idle,
);

// Rule for a different host — should NOT appear.
final _otherRule = PortForward(
  id: 'r3',
  label: 'other',
  type: ForwardType.local,
  localPort: 8080,
  remoteHost: 'other',
  remotePort: 80,
  hostId: 'h99',
  status: ForwardStatus.idle,
);

// ---------------------------------------------------------------------------
// Pump helper
// ---------------------------------------------------------------------------

Future<_FakePortForwardService> _pump(WidgetTester tester) async {
  final provider = _FakePortForwardProvider([_activeRule, _stoppedRule, _otherRule]);
  final service = _FakePortForwardService();

  await tester.pumpWidget(MaterialApp(
    theme: buildMobileTheme(),
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<PortForwardProvider>.value(value: provider),
        Provider<PortForwardService>.value(value: service),
      ],
      child: MobilePortForwardScreen(host: _host),
    ),
  ));
  await tester.pump();
  return service;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows host label in header', (tester) async {
    await _pump(tester);
    expect(find.text('db-prod'), findsAtLeastNWidgets(1));
  });

  testWidgets('renders active LOCAL rule mono line', (tester) async {
    await _pump(tester);
    expect(find.textContaining(':5432 → db-prod:5432'), findsOneWidget);
  });

  testWidgets('renders stopped DYNAMIC rule mono line', (tester) async {
    await _pump(tester);
    expect(find.textContaining('SOCKS5 :1080'), findsOneWidget);
  });

  testWidgets('does not render rule for a different host', (tester) async {
    await _pump(tester);
    expect(find.textContaining(':8080'), findsNothing);
  });

  testWidgets('shows Add forwarding rule button', (tester) async {
    await _pump(tester);
    expect(find.text('Add forwarding rule'), findsOneWidget);
  });

  testWidgets('tapping play icon on stopped rule calls service.start',
      (tester) async {
    final svc = await _pump(tester);
    await tester.tap(find.byIcon(Icons.play_circle_outline));
    await tester.pump();
    expect(svc.startedIds, contains(_stoppedRule.id));
  });

  testWidgets('tapping stop icon on active rule calls service.stop',
      (tester) async {
    final svc = await _pump(tester);
    await tester.tap(find.byIcon(Icons.stop_circle_outlined));
    await tester.pump();
    expect(svc.stoppedIds, contains(_activeRule.id));
  });
}
