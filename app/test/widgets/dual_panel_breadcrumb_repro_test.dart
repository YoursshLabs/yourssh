import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/dual_panel_sftp_screen.dart';
import 'package:yourssh/widgets/path_breadcrumb.dart';

/// Repro for "breadcrumb not visible in the two-panel layout".
void main() {
  testWidgets('connected remote slot shows the path breadcrumb',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final notifier = ValueNotifier<bool>(false);
    addTearDown(notifier.dispose);
    final storage = StorageService();
    final hostProvider = HostProvider(storage);
    await hostProvider.addHost(Host(
      label: 'alpha',
      host: '127.0.0.1',
      username: 'root',
      authType: AuthType.password,
    ));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SshService>(create: (_) => SshService(storage)),
          ChangeNotifierProvider.value(value: hostProvider),
        ],
        child: MaterialApp(
          home: Scaffold(body: DualPanelSftpScreen(connectionNotifier: notifier)),
        ),
      ),
    );
    await tester.pump();

    // Left slot is local: breadcrumb already expected there.
    expect(find.byType(PathBreadcrumb), findsOneWidget);

    // Connect the right slot to the host.
    await tester.tap(find.text('Select host'));
    await tester.pump();
    await tester.tap(find.text('alpha'));
    await tester.pump();

    // Remote panel path bar must show a breadcrumb too (issue #41).
    expect(find.byType(PathBreadcrumb), findsNWidgets(2));

    // Unified headers: the remote chip shows the host LABEL (not user@host),
    // and both panels expose Filter and Actions in the header row.
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('root@127.0.0.1'), findsNothing);
    expect(find.text('Filter'), findsNWidgets(2));
    expect(find.text('Actions'), findsNWidgets(2));
  });
}
