import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/mobile/security/tofu_watcher.dart';
import 'package:yourssh/providers/known_hosts_provider.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/theme/app_theme.dart' show ysRootBuilder;
import 'package:yourssh_ui/yourssh_ui.dart' show YsColors;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows a dialog on host-key mismatch and Trust accepts',
      (tester) async {
    final kh = KnownHostsProvider(StorageService());
    await tester.pumpWidget(MaterialApp(builder: ysRootBuilder,
      home: ChangeNotifierProvider.value(
        value: kh,
        child: const TofuWatcher(child: Scaffold(body: SizedBox())),
      ),
    ));

    final fp1 = Uint8List.fromList(List.filled(16, 1));
    final fp2 = Uint8List.fromList(List.filled(16, 2));
    await kh.verifyHostKey('h', 22, 'ssh-ed25519', fp1); // first-use trust
    final future = kh.verifyHostKey('h', 22, 'ssh-ed25519', fp2); // mismatch
    await tester.pumpAndSettle();

    expect(find.textContaining('host key'), findsOneWidget);
    await tester.tap(find.text('Trust'));
    await tester.pumpAndSettle();
    expect(await future, isTrue);
  });

  testWidgets('Enter on a changed host key rejects (Reject holds focus)',
      (tester) async {
    final kh = KnownHostsProvider(StorageService());
    await tester.pumpWidget(MaterialApp(
      builder: ysRootBuilder,
      home: ChangeNotifierProvider.value(
        value: kh,
        child: const TofuWatcher(child: Scaffold(body: SizedBox())),
      ),
    ));
    final fp1 = Uint8List.fromList(List.filled(16, 1));
    final fp2 = Uint8List.fromList(List.filled(16, 2));
    await kh.verifyHostKey('h', 22, 'ssh-ed25519', fp1);
    final future = kh.verifyHostKey('h', 22, 'ssh-ed25519', fp2);
    await tester.pumpAndSettle();
    expect(find.text('Trust'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(await future, isFalse);
  });

  testWidgets('warning is mutedForeground and scrollable at 600x400 x1.3',
      (tester) async {
    tester.view.physicalSize = const Size(600, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final kh = KnownHostsProvider(StorageService());
    await tester.pumpWidget(MaterialApp(
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c)
            .copyWith(textScaler: const TextScaler.linear(1.3)),
        child: ysRootBuilder(c, child),
      ),
      home: ChangeNotifierProvider.value(
        value: kh,
        child: const TofuWatcher(child: Scaffold(body: SizedBox())),
      ),
    ));
    final fp1 = Uint8List.fromList(List.filled(16, 1));
    final fp2 = Uint8List.fromList(List.filled(16, 2));
    await kh.verifyHostKey('h', 22, 'ssh-ed25519', fp1);
    final future = kh.verifyHostKey('h', 22, 'ssh-ed25519', fp2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final warning = find.textContaining('man-in-the-middle');
    expect(warning, findsOneWidget);
    expect(tester.widget<Text>(warning).style!.color, YsColors.mutedForeground);
    expect(
      find.ancestor(of: warning, matching: find.byType(SingleChildScrollView)),
      findsOneWidget,
    );
    await tester.ensureVisible(warning);
    await tester.pumpAndSettle();
    final screen = Offset.zero & const Size(600, 400);
    expect(screen.contains(tester.getBottomRight(warning)), isTrue);
    expect(screen.contains(tester.getCenter(find.text('Trust'))), isTrue);
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(await future, isFalse);
  });

  testWidgets('fingerprints use YsColors tokens', (tester) async {
    final kh = KnownHostsProvider(StorageService());
    await tester.pumpWidget(MaterialApp(
      builder: ysRootBuilder,
      home: ChangeNotifierProvider.value(
        value: kh,
        child: const TofuWatcher(child: Scaffold(body: SizedBox())),
      ),
    ));
    final fp1 = Uint8List.fromList(List.filled(16, 1));
    final fp2 = Uint8List.fromList(List.filled(16, 2));
    await kh.verifyHostKey('h', 22, 'ssh-ed25519', fp1);
    final future = kh.verifyHostKey('h', 22, 'ssh-ed25519', fp2);
    await tester.pumpAndSettle();
    expect(
        tester.widget<Text>(find.textContaining('Old:')).style!.color,
        YsColors.mutedForeground);
    expect(tester.widget<Text>(find.textContaining('New:')).style!.color,
        YsColors.foreground);
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(await future, isFalse);
  });
}
