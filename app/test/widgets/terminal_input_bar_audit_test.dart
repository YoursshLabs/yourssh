import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/command_history_provider.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/audit_service.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
import 'package:yourssh/widgets/terminal_input_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('submitting a command records an input audit event',
      (tester) async {
    final audit = AuditService()..initInMemory();
    final sessions =
        SessionProvider(SshService(StorageService()), TabMetadataService());

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CommandHistoryProvider()),
        ChangeNotifierProvider.value(value: sessions),
        Provider<AuditService>.value(value: audit),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: TerminalInputBar(
              sessionId: 's1', onSubmit: (_) {}, onDismiss: () {}),
        ),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'systemctl restart nginx');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    final rows = audit.query(const AuditFilter(type: 'input'));
    expect(rows.length, 1);
    expect(rows.single.command, 'systemctl restart nginx');
    expect(rows.single.meta['source'], 'input-bar');
    sessions.dispose();
    audit.dispose();
  });
}
