import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/keep_alive_offstage.dart';

/// Stateful probe: counts how many times its State was created and holds
/// a mutable counter so tests can detect State loss across rebuilds.
class _Probe extends StatefulWidget {
  const _Probe();

  static int statesCreated = 0;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int counter = 0;

  @override
  void initState() {
    super.initState();
    _Probe.statesCreated++;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => counter++),
      child: Text('counter:$counter', textDirection: TextDirection.ltr),
    );
  }
}

Widget _harness(bool active) {
  return MaterialApp(
    home: KeepAliveOffstage(
      active: active,
      child: const _Probe(),
    ),
  );
}

void main() {
  setUp(() => _Probe.statesCreated = 0);

  testWidgets('does not build child until first activated', (tester) async {
    await tester.pumpWidget(_harness(false));
    expect(_Probe.statesCreated, 0);
    expect(find.byType(_Probe, skipOffstage: false), findsNothing);
  });

  testWidgets('shows child when active', (tester) async {
    await tester.pumpWidget(_harness(true));
    expect(_Probe.statesCreated, 1);
    expect(find.text('counter:0'), findsOneWidget);
  });

  testWidgets('keeps child State alive while inactive and restores it',
      (tester) async {
    await tester.pumpWidget(_harness(true));

    // Mutate child state.
    await tester.tap(find.byType(_Probe));
    await tester.pump();
    expect(find.text('counter:1'), findsOneWidget);

    // Deactivate: child hidden but State must survive.
    await tester.pumpWidget(_harness(false));
    expect(find.text('counter:1'), findsNothing); // not visible
    expect(find.text('counter:1', skipOffstage: false),
        findsOneWidget); // still mounted offstage
    expect(_Probe.statesCreated, 1); // no new State

    // Reactivate: same State, counter preserved.
    await tester.pumpWidget(_harness(true));
    expect(find.text('counter:1'), findsOneWidget);
    expect(_Probe.statesCreated, 1);
  });

  testWidgets('offstage child is not hit-testable', (tester) async {
    await tester.pumpWidget(_harness(true));
    await tester.pumpWidget(_harness(false));
    // Tapping where the child was must not reach it.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpWidget(_harness(true));
    expect(find.text('counter:0'), findsOneWidget);
  });
}
