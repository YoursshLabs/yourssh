import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/host_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/widgets/dual_panel_sftp_screen.dart';
import 'package:yourssh/widgets/local_file_panel.dart';
import 'package:yourssh/widgets/sftp_panel.dart';
import 'package:yourssh/widgets/source_picker_dialog.dart';

void main() {
  late ValueNotifier<bool> notifier;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    notifier = ValueNotifier<bool>(false);
  });

  tearDown(() => notifier.dispose());

  Future<void> pumpScreen(WidgetTester tester) async {
    final storage = StorageService();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SshService>(create: (_) => SshService(storage)),
          ChangeNotifierProvider(create: (_) => HostProvider(storage)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: DualPanelSftpScreen(connectionNotifier: notifier),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('left slot defaults to Local, right slot is unconnected',
      (tester) async {
    await pumpScreen(tester);
    expect(find.byType(LocalFilePanel), findsOneWidget);
    expect(find.byType(SftpPanel), findsOneWidget);
    expect(find.text('Connect to host'), findsOneWidget);
  });

  testWidgets('selecting Local in the right slot renders a local panel',
      (tester) async {
    await pumpScreen(tester);

    // Open the source picker from the unconnected right slot.
    await tester.tap(find.text('Select host'));
    await tester.pump();
    expect(find.byType(SourcePickerDialog), findsOneWidget);

    await tester.tap(find.descendant(
        of: find.byType(SourcePickerDialog), matching: find.text('Local')));
    await tester.pump();

    expect(find.byType(LocalFilePanel), findsNWidgets(2));
    expect(find.byType(SftpPanel), findsNothing);
    expect(notifier.value, isFalse); // both slots local → no remote connection
  });
}
