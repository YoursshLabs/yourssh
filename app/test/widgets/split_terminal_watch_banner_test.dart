import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/plugin_provider.dart';
import 'package:yourssh/providers/recording_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/providers/share_provider.dart';
import 'package:yourssh/providers/shell_integration_provider.dart';
import 'package:yourssh/providers/sync_provider.dart';
import 'package:yourssh/providers/terminal_layout_provider.dart';
import 'package:yourssh/services/recording_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
import 'package:yourssh/widgets/split_terminal_view.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('read-only watch banner has its own informational cue',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final sessions =
        SessionProvider(SshService(StorageService()), TabMetadataService());
    final share = ShareProvider(syncProvider: SyncProvider());
    final watch = SshSession.watch(watchedTitle: 'prod-web');
    sessions.sessions.add(watch);
    sessions.setActive(watch.id);

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionProvider>.value(value: sessions),
        ChangeNotifierProvider(create: (_) => TerminalLayoutProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => ShellIntegrationProvider()),
        ChangeNotifierProvider<ShareProvider>.value(value: share),
        ChangeNotifierProvider(
            create: (_) => RecordingProvider(RecordingService(),
                getPath: () => '/tmp')),
        ChangeNotifierProvider(create: (_) => PluginProvider(plugins: [])),
      ],
      child: ysTestApp(const SplitTerminalView()),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    final label = find.text('Watching: prod-web · Read-only');
    expect(label, findsOneWidget);
    expect(tester.widget<Text>(label).style?.color, YsColors.accentText);
    final banner = tester.widget<Container>(find
        .ancestor(of: label, matching: find.byType(Container))
        .first);
    expect(banner.color, YsColors.primary.withValues(alpha: 0.12));
    // Distinct from the in-control (green) and ended (red) states.
    expect(banner.color, isNot(YsColors.ok.withValues(alpha: 0.12)));
    expect(banner.color, isNot(YsColors.error.withValues(alpha: 0.14)));
    expect(tester.takeException(), isNull);
  });
}
