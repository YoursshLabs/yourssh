import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/panel_source.dart';
import 'package:yourssh/widgets/source_picker_dialog.dart';

Host _host(String label) => Host(
      label: label,
      host: '10.0.0.1',
      username: 'root',
      authType: AuthType.password,
    );

void main() {
  late List<Host> hosts;
  PanelSource? picked;

  Widget harness({PanelSource? current}) {
    return MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            picked = await showDialog<PanelSource>(
              context: context,
              builder: (_) => SourcePickerDialog(hosts: hosts, current: current),
            );
          },
          child: const Text('open'),
        ),
      ),
    );
  }

  setUp(() {
    hosts = [_host('alpha'), _host('beta')];
    picked = null;
  });

  Future<void> open(WidgetTester tester, {PanelSource? current}) async {
    await tester.pumpWidget(harness(current: current));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows a pinned Local entry plus all hosts', (tester) async {
    await open(tester);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);
  });

  testWidgets('selecting Local returns LocalSource', (tester) async {
    await open(tester);
    await tester.tap(find.text('Local'));
    await tester.pumpAndSettle();
    expect(picked, const LocalSource());
  });

  testWidgets('selecting a host returns HostSource for that host', (tester) async {
    await open(tester);
    await tester.tap(find.text('beta'));
    await tester.pumpAndSettle();
    expect(picked, HostSource(hosts[1]));
  });
}
