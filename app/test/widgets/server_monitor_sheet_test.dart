import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/models/firewall_status.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/system_snapshot.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/widgets/server_monitor_sheet.dart';

class _FakeSsh extends Fake implements SshService {
  @override
  Future<({String stdout, String stderr, int exitCode})> exec(
    Host host,
    String command, {
    String? auditSource = 'app',
  }) async =>
      // Never completes — simulates an in-flight exec so loading indicators remain
      Completer<({String stdout, String stderr, int exitCode})>().future;
}

Widget _wrap(Widget child) => MultiProvider(
      providers: [
        Provider<SshService>(create: (_) => _FakeSsh()),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

Host _host() => Host(
      id: 'h1',
      label: 'ubuntu-prod',
      host: 'example.com',
      port: 22,
      username: 'root',
    );

void main() {
  group('ServerMonitorSheet', () {
    testWidgets('shows not-connected message when testIsConnected is false',
        (tester) async {
      await tester.pumpWidget(
        _wrap(ServerMonitorSheet(host: _host(), testIsConnected: false)),
      );
      expect(find.textContaining('No active session'), findsOneWidget);
    });

    testWidgets('shows loading indicators while awaiting first snapshot',
        (tester) async {
      await tester.pumpWidget(
        _wrap(ServerMonitorSheet(host: _host(), testIsConnected: true)),
      );
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('renders system section after debugSetSnapshot', (tester) async {
      await tester.pumpWidget(
        _wrap(ServerMonitorSheet(host: _host(), testIsConnected: true)),
      );
      final state = tester.state<ServerMonitorSheetState>(
        find.byType(ServerMonitorSheet),
      );
      state.debugSetSnapshot(SystemSnapshot(
        cpuPercent: 42.5,
        totalMemBytes: 8 * 1024 * 1024 * 1024,
        usedMemBytes: 3 * 1024 * 1024 * 1024,
        disks: [
          DiskMount(
              source: '/dev/sda1',
              mountPoint: '/',
              totalKb: 100000,
              usedKb: 45000),
        ],
        uptime: const Duration(hours: 14, minutes: 3),
        ports: [
          PortEntry(
              protocol: 'tcp',
              localAddress: '0.0.0.0',
              localPort: 22,
              process: 'sshd'),
        ],
        timestamp: DateTime.now(),
      ));
      await tester.pump();
      expect(find.textContaining('42'), findsOneWidget);
      expect(find.textContaining('sshd'), findsOneWidget);
    });

    testWidgets('renders firewall section after debugSetFirewall',
        (tester) async {
      await tester.pumpWidget(
        _wrap(ServerMonitorSheet(host: _host(), testIsConnected: true)),
      );
      final state = tester.state<ServerMonitorSheetState>(
        find.byType(ServerMonitorSheet),
      );
      state.debugSetFirewall(const FirewallStatus(
        type: FirewallType.ufw,
        enabled: true,
        defaultInboundPolicy: 'DENY',
        rules: [
          FirewallRule(
              description: '22/tcp  ALLOW  anywhere', action: 'ALLOW'),
        ],
      ));
      await tester.pump();
      expect(find.textContaining('ufw'), findsOneWidget);
      expect(find.textContaining('DENY'), findsOneWidget);
    });

    testWidgets('renders no-firewall message for FirewallType.none',
        (tester) async {
      await tester.pumpWidget(
        _wrap(ServerMonitorSheet(host: _host(), testIsConnected: true)),
      );
      final state = tester.state<ServerMonitorSheetState>(
        find.byType(ServerMonitorSheet),
      );
      state.debugSetFirewall(const FirewallStatus(
        type: FirewallType.none,
        enabled: false,
        rules: [],
      ));
      await tester.pump();
      expect(find.textContaining('No firewall'), findsOneWidget);
    });
  });
}
