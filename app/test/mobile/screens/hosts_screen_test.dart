import 'package:yourssh/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yourssh/mobile/screens/mobile_hosts_screen.dart';
import 'package:yourssh/mobile/services/host_reachability_probe.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/mobile/widgets/tag_chip.dart';
import 'package:yourssh/mobile/widgets/host_card.dart';
import 'package:yourssh/mobile/screens/mobile_add_host_screen.dart';
import 'package:yourssh/providers/key_provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import 'package:yourssh/mobile/widgets/mobile_fab.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

var _probeCalls = 0;

Finder _filterChip(String label) => find.byWidgetPredicate(
    (w) => w is TagChip && w.large && w.label == label);

Future<void> _pump(WidgetTester tester, HostProvider hosts) async {
  final sessions = SessionProvider(SshService(StorageService()), TabMetadataService());
  _probeCalls = 0;
  final probe = HostReachabilityProbe(
    connector: (h, p, to) async => _probeCalls++, // no real network in tests
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<HostProvider>.value(value: hosts),
        ChangeNotifierProvider<SessionProvider>.value(value: sessions),
        ChangeNotifierProvider<HostReachabilityProbe>.value(value: probe),
        ChangeNotifierProvider<KeyProvider>(create: (_) => KeyProvider()),
      ],
      child: MaterialApp(
        theme: buildMobileTheme(),
        builder: ysRootBuilderTouch,
        home: const MobileHostsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows title "Hosts"', (tester) async {
    await _pump(tester, HostProvider(StorageService()));
    expect(find.text('Hosts'), findsOneWidget);
  });

  testWidgets('renders both host labels and Production section header', (tester) async {
    final hosts = HostProvider(StorageService());
    await hosts.addHost(Host(
      label: 'web-01',
      host: '10.0.0.1',
      username: 'root',
      tags: ['Production'],
    ));
    await hosts.addHost(Host(
      label: 'db-01',
      host: '10.0.0.2',
      username: 'root',
      tags: ['Production'],
    ));

    await _pump(tester, hosts);

    expect(find.text('web-01'), findsOneWidget);
    expect(find.text('db-01'), findsOneWidget);
    expect(find.text('PRODUCTION'), findsOneWidget);
  });

  testWidgets('FAB is present', (tester) async {
    await _pump(tester, HostProvider(StorageService()));
    expect(find.byType(MobileFab), findsOneWidget);
  });

  group('forui screen behaviour', () {
    Future<HostProvider> seeded({String label = 'web-01'}) async {
      final hosts = HostProvider(StorageService());
      await hosts.addHost(Host(
        label: label,
        host: '10.0.0.1',
        username: 'root',
        tags: ['Production'],
      ));
      return hosts;
    }

    testWidgets('360x640 with a 60-char label: no overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(tester, await seeded(label: 'x' * 60));
      expect(tester.takeException(), isNull);
      expect(find.text('x' * 60), findsOneWidget);
    });

    testWidgets('primary actions have >=44 px hit size', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(tester, await seeded());
      final fab = find.descendant(
        of: find.byType(MobileFab),
        matching: find.bySubtype<FTappable>(),
      );
      expect(tester.getSize(fab).shortestSide, greaterThanOrEqualTo(44));
      expect(tester.getSize(find.byType(FTextField)).height,
          greaterThanOrEqualTo(44));
      final chips = find.descendant(
        of: find.byType(TagChip),
        matching: find.bySubtype<FTappable>(),
      );
      expect(chips, findsNWidgets(2)); // All + Production
      for (var i = 0; i < 2; i++) {
        expect(tester.getSize(chips.at(i)).height, greaterThanOrEqualTo(44));
      }
      expect(tester.getSize(find.byType(HostCard)).height,
          greaterThanOrEqualTo(44));
      // The chip row is tall enough for the hit area (nothing clipped).
      expect(tester.takeException(), isNull);
    });

    testWidgets('folder chip filters; tapping it again clears', (tester) async {
      final hosts = HostProvider(StorageService());
      await hosts.addHost(Host(
          label: 'a', host: '1.1.1.1', username: 'r', tags: ['One']));
      await hosts.addHost(Host(
          label: 'b', host: '2.2.2.2', username: 'r', tags: ['Two']));
      await _pump(tester, hosts);
      await tester.tap(_filterChip('One'));
      await tester.pumpAndSettle();
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsNothing);
      await tester.tap(_filterChip('One'));
      await tester.pumpAndSettle();
      expect(find.text('b'), findsOneWidget);
    });

    testWidgets('long-press opens Edit/Delete sheet; Edit opens the form',
        (tester) async {
      await _pump(tester, await seeded());
      await tester.longPress(find.text('web-01'));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.byType(MobileAddHostScreen), findsOneWidget);
      expect(find.text('Edit host'), findsOneWidget);
    });

    testWidgets('Delete asks for confirmation (Cancel focused); Cancel keeps '
        'the host, confirm removes it', (tester) async {
      final hosts = await seeded();
      await _pump(tester, hosts);
      await tester.longPress(find.text('web-01'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete web-01?'), findsOneWidget);
      expect(find.text('This removes the saved host and its credentials.'),
          findsOneWidget);
      final cancel = find.widgetWithText(FButton, 'Cancel');
      expect(tester.widget<FButton>(cancel).autofocus, isTrue);
      expect(tester.widget<FButton>(find.widgetWithText(FButton, 'Delete'))
          .autofocus, isFalse);

      await tester.tap(cancel);
      await tester.pumpAndSettle();
      expect(hosts.allHosts, hasLength(1));

      await tester.longPress(find.text('web-01'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(hosts.allHosts, isEmpty);
    });

    testWidgets('FAB opens the New host form', (tester) async {
      await _pump(tester, await seeded());
      await tester.tap(find.byType(MobileFab));
      await tester.pumpAndSettle();
      expect(find.text('New host'), findsOneWidget);
    });

    testWidgets('empty state "Add host" opens the form', (tester) async {
      await _pump(tester, HostProvider(StorageService()));
      await tester.tap(find.widgetWithText(FButton, 'Add host'));
      await tester.pumpAndSettle();
      expect(find.text('New host'), findsOneWidget);
    });

    testWidgets('pull-to-refresh re-probes hosts', (tester) async {
      await _pump(tester, await seeded());
      final before = _probeCalls;
      await tester.fling(find.text('web-01'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(_probeCalls, greaterThan(before));
    });

    testWidgets('search field keeps focus traversal: typing filters live',
        (tester) async {
      final hosts = await seeded();
      await hosts.addHost(Host(label: 'db-1', host: '10.0.0.2', username: 'a'));
      await _pump(tester, hosts);
      await tester.tap(find.byType(FTextField));
      await tester.pump();
      await tester.enterText(find.byType(FTextField), 'db');
      await tester.pumpAndSettle();
      expect(find.text('web-01'), findsNothing);
      expect(find.text('db-1'), findsOneWidget);
    });
  });
}
