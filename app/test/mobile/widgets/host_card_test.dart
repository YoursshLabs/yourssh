import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/mobile/widgets/host_card.dart';

void main() {
  testWidgets('renders label, user@ip subtitle, and latency badge', (t) async {
    final host = Host(
      label: 'web-01',
      host: '10.0.4.21',
      port: 22,
      username: 'deploy',
    );
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HostCard(
          host: host,
          online: true,
          latencyMs: 24,
          onTap: () {},
        ),
      ),
    ));
    expect(find.text('web-01'), findsOneWidget);
    expect(find.text('deploy@10.0.4.21'), findsOneWidget);
    expect(find.text('24ms'), findsOneWidget);
  });
}
