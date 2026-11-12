import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/models/known_host.dart';
import 'package:yourssh/providers/known_hosts_provider.dart';
import 'package:yourssh/widgets/known_hosts_screen.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

KnownHost _kh(String host, {String fp = 'aa:bb:cc:dd:ee:ff:00:11'}) => KnownHost(
  host: host,
  port: 22,
  keyType: 'ssh-ed25519',
  fingerprint: fp,
  addedAt: DateTime(2026, 1, 1),
);

Widget _app(KnownHostsProvider p) => ChangeNotifierProvider.value(
  value: p,
  child: ysTestApp(const KnownHostsScreen()),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty state', (tester) async {
    await tester.pumpWidget(_app(KnownHostsProvider.forTest([])));
    await tester.pumpAndSettle();
    expect(find.text('No known hosts yet'), findsOneWidget);
    expect(find.text('Connect to a server to add one.'), findsOneWidget);
    expect(find.text('Known Hosts'), findsOneWidget);
    expect(find.text('IMPORT'), findsOneWidget);
  });

  testWidgets('lists host:port, key type and a short fingerprint in mono',
      (tester) async {
    await tester.pumpWidget(_app(KnownHostsProvider.forTest([_kh('web.local')])));
    await tester.pumpAndSettle();
    expect(find.text('web.local:22'), findsOneWidget);
    expect(find.text('ssh-ed25519'), findsOneWidget);
    final fp = tester.widget<Text>(find.text('aa:bb:cc:dd…'));
    expect(fp.style?.fontFamily, kYsMonoFontFamily);
    expect(find.byTooltip('aa:bb:cc:dd:ee:ff:00:11'), findsOneWidget);
    expect(find.byTooltip('Copy fingerprint'), findsOneWidget);
    expect(find.byTooltip('Remove'), findsOneWidget);
  });

  testWidgets('in-tile buttons fire: copy fingerprint and remove',
      (tester) async {
    final p = KnownHostsProvider.forTest([_kh('web.local'), _kh('db.local')]);
    String? clip;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clip = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(_app(p));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Copy fingerprint').first);
    await tester.pump();
    expect(clip, 'aa:bb:cc:dd:ee:ff:00:11');

    await tester.tap(find.byTooltip('Remove').first);
    await tester.pumpAndSettle();
    expect(p.hosts, hasLength(1));
    expect(p.hosts.single.host, 'db.local');
  });

  testWidgets('900x600 with 60-char host and fingerprint does not overflow',
      (tester) async {
    final long = 'h' * 60;
    final p = KnownHostsProvider.forTest([
      _kh(long, fp: List.filled(20, 'ab').join(':')),
    ]);
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(p));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
