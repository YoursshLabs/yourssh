import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/links/mobile_links.dart';
import 'package:yourssh/mobile/mobile_bootstrap.dart';
import 'package:yourssh/mobile/security/app_lock_gate.dart';
import 'package:yourssh/mobile/util/mobile_prefs.dart';

import '../../helpers/ys_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const url = MethodChannel('yourssh/url');
  const ssh = MethodChannel('yourssh/ssh_url');

  Future<void> send(WidgetTester t, String name, String link) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(name,
            const StandardMethodCodec().encodeMethodCall(MethodCall('open', link)),
            (_) {});
    // Real async: SharedPreferences and the providers' loads.
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  }

  tearDown(() => mobileAppLocked.value = false);

  testWidgets('an ssh:// link to an unknown target asks only after unlock '
      '(nothing saved)', (tester) async {
    SharedPreferences.setMockInitialValues({kSshLinksPrefKey: true});
    final b = MobileBootstrap();
    await tester.pumpWidget(MultiProvider(
      providers: b.providers,
      child: ysTestApp(
          Navigator(
            key: b.navigatorKey,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('home'))),
          ),
          touch: true),
    ));
    MobileLinks(
            bootstrap: b,
            navigator: b.navigatorKey,
            appVersion: '1',
            urlChannel: url,
            sshChannel: ssh)
        .attach();

    mobileAppLocked.value = true;
    await send(tester, 'yourssh/ssh_url', 'ssh://demo@203.0.113.7');
    await tester.pump();
    expect(find.text('Open ssh:// link?'), findsNothing);

    mobileAppLocked.value = false;
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Open ssh:// link?'), findsOneWidget);
    expect(find.textContaining('demo@203.0.113.7:22'), findsOneWidget);
    // Nothing was saved by asking.
    expect(b.hostProvider.allHosts, isEmpty);
    b.dispose();
  });
}
