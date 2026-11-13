import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/agent_probe.dart';
import 'package:yourssh/widgets/agent_status_line.dart';
import 'package:yourssh_ui/yourssh_ui.dart' show FCircularProgress;

import '../helpers/ys_test_app.dart';

void main() {
  Widget wrap(Widget child) => ysTestApp(child);

  testWidgets('probes on mount and renders the system-agent state',
      (tester) async {
    await tester.pumpWidget(wrap(AgentStatusLine(
      probe: () async => const AgentProbeSystem(3),
    )));
    expect(find.text('Checking SSH agent…'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(
        find.text('System agent connected — 3 identities'), findsOneWidget);
  });

  testWidgets('renders the Keychain fallback state', (tester) async {
    await tester.pumpWidget(wrap(AgentStatusLine(
      probe: () async => const AgentProbeKeychain(1),
    )));
    await tester.pumpAndSettle();
    expect(
      find.text('No system agent — 1 app Keychain key will be offered instead'),
      findsOneWidget,
    );
  });

  testWidgets('renders the nothing-available state with the ssh-add hint',
      (tester) async {
    await tester.pumpWidget(wrap(AgentStatusLine(
      probe: () async => const AgentProbeNothing(),
    )));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Run "ssh-add <key>" or add a key in Keychain'),
      findsOneWidget,
    );
  });

  testWidgets('renders the agent-error state with detail', (tester) async {
    await tester.pumpWidget(wrap(AgentStatusLine(
      probe: () async => const AgentProbeNothing('boom'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('SSH agent error: boom'), findsOneWidget);
  });

  testWidgets('refresh re-runs the probe', (tester) async {
    var calls = 0;
    await tester.pumpWidget(wrap(AgentStatusLine(
      probe: () async => AgentProbeSystem(++calls),
    )));
    await tester.pumpAndSettle();
    expect(find.text('System agent connected — 1 identity'), findsOneWidget);

    await tester.tap(find.byTooltip('Check again'));
    await tester.pumpAndSettle();
    expect(find.text('System agent connected — 2 identities'), findsOneWidget);
  });

  testWidgets('shows a spinner instead of the refresh icon while in flight',
      (tester) async {
    var completer = Completer<AgentProbeResult>();
    await tester.pumpWidget(wrap(AgentStatusLine(
      probe: () => completer.future,
    )));

    // Initial probe in flight: spinner visible, refresh hidden.
    expect(find.byType(FCircularProgress), findsOneWidget);
    expect(find.byTooltip('Check again'), findsNothing);

    completer.complete(const AgentProbeSystem(1));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Check again'), findsOneWidget);
    expect(find.byType(FCircularProgress), findsNothing);

    // Refresh returns to the loading state until the new probe resolves.
    completer = Completer<AgentProbeResult>();
    await tester.tap(find.byTooltip('Check again'));
    await tester.pump();
    expect(find.text('Checking SSH agent…'), findsOneWidget);
    expect(find.byType(FCircularProgress), findsOneWidget);

    completer.complete(const AgentProbeKeychain(2));
    await tester.pumpAndSettle();
    expect(
      find.text('No system agent — 2 app Keychain keys will be offered instead'),
      findsOneWidget,
    );
  });
}
