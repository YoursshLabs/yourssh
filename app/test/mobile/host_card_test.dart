import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/mobile/widgets/host_card.dart';
import 'package:yourssh/mobile/widgets/status_dot.dart';

void main() {
  testWidgets('renders label, target, tags, and fires onTap', (t) async {
    final host = Host(
      label: 'Production Web',
      host: '10.0.0.5',
      port: 22,
      username: 'root',
      tags: const ['prod', 'nginx'],
    );
    var tapped = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HostCard(
          host: host,
          state: HostConnState.connected,
          onTap: () => tapped = true,
        ),
      ),
    ));
    expect(find.text('Production Web'), findsOneWidget);
    expect(find.text('root@10.0.0.5:22'), findsOneWidget);
    expect(find.text('prod'), findsOneWidget);
    expect(find.text('nginx'), findsOneWidget);
    await t.tap(find.text('Production Web'));
    expect(tapped, isTrue);
  });
}
