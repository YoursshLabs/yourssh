import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh/services/agent_probe.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/host_detail_panel.dart';

import '../helpers/ys_test_app.dart';

/// MainScreen mounts the editor with `hostEditorKey(_editingHost, serial)` and
/// bumps the serial on every open; this harness mirrors that wiring.
class _Shell extends StatefulWidget {
  const _Shell({required this.onSave});
  final void Function(Host host, String password) onSave;
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  Host? editing = _a; // host A is already open when each test starts
  int serial = 0;

  void open({Host? existing}) => setState(() {
        serial++;
        editing = existing;
      });

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Row(children: [
            TextButton(
              key: const ValueKey('open-a'),
              onPressed: () => open(existing: _a),
              child: const Text('A'),
            ),
            TextButton(
              key: const ValueKey('open-b'),
              onPressed: () => open(existing: _b),
              child: const Text('B'),
            ),
            TextButton(
              key: const ValueKey('open-new'),
              onPressed: open,
              child: const Text('New'),
            ),
            TextButton(
              key: const ValueKey('open-dup'),
              onPressed: () => open(existing: _dup),
              child: const Text('Dup'),
            ),
          ]),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: HostDetailPanel(
                key: hostEditorKey(editing, serial),
                existing: editing,
                agentProbe: () async => const AgentProbeSystem(1),
                onClose: () {},
                onSave: (h, p) async => widget.onSave(h, p),
              ),
            ),
          ),
        ],
      );
}

final _a = Host(id: 'a', label: 'Alpha', host: '1.1.1.1', username: 'ua');
final _b = Host(id: 'b', label: 'Bravo', host: '2.2.2.2', username: 'ub');
final _dup =
    Host(id: 'dup', label: 'Alpha (copy)', host: '1.1.1.1', username: 'ua');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => call.method == 'readAll' ? <String, String>{} : null,
        );
  });

  Host? saved;

  Future<void> pump(WidgetTester tester) async {
    saved = null;
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final hosts = HostProvider(StorageService());
    await tester.runAsync(() => hosts.ready);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<KeyProvider>(create: (_) => KeyProvider()),
        ChangeNotifierProvider<HostProvider>.value(value: hosts),
        Provider<SshService>(create: (_) => SshService(StorageService())),
      ],
      child: ysTestApp(_Shell(onSave: (h, _) => saved = h)),
    ));
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester, String key) => tester
      .widget<EditableText>(find.descendant(
          of: find.byKey(ValueKey(key)), matching: find.byType(EditableText)))
      .controller
      .text;

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  testWidgets('A -> Edit B shows B and Save writes B', (tester) async {
    await pump(tester);
    expect(text(tester, 'host-label-field'), 'Alpha');
    await tap(tester, 'open-b');
    expect(text(tester, 'host-label-field'), 'Bravo');
    expect(text(tester, 'host-address-field'), '2.2.2.2');
    expect(text(tester, 'host-username-field'), 'ub');
    await tap(tester, 'host-save-button');
    expect(saved?.id, 'b');
    expect(saved?.label, 'Bravo');
    expect(saved?.host, '2.2.2.2');
  });

  testWidgets('A -> New shows an empty form', (tester) async {
    await pump(tester);
    await tap(tester, 'open-new');
    expect(text(tester, 'host-label-field'), '');
    expect(text(tester, 'host-address-field'), '');
    expect(text(tester, 'host-username-field'), '');
  });

  testWidgets('A -> Duplicate shows the duplicate prefill', (tester) async {
    await pump(tester);
    await tap(tester, 'open-dup');
    expect(text(tester, 'host-label-field'), 'Alpha (copy)');
  });

  testWidgets('New -> New resets typed input', (tester) async {
    await pump(tester);
    await tap(tester, 'open-new');
    expect(text(tester, 'host-label-field'), '');
    await tester.enterText(
        find.descendant(
            of: find.byKey(const ValueKey('host-label-field')),
            matching: find.byType(EditableText)),
        'typed');
    expect(text(tester, 'host-label-field'), 'typed');
    await tap(tester, 'open-new');
    expect(text(tester, 'host-label-field'), '');
  });
}
