// Smoke tests for the terminal-sharing dialogs (host: ShareSessionDialog,
// guest: JoinShareDialog), pumped the way the app opens them.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/share_provider.dart';
import 'package:yourssh/providers/sync_provider.dart';
import 'package:yourssh/services/share_crypto.dart';
import 'package:yourssh/widgets/join_share_dialog.dart';
import 'package:yourssh/widgets/share_session_dialog.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../helpers/ys_test_app.dart';

class _FakeSync extends SyncProvider {
  bool configured = true;

  @override
  bool get isSupabaseConfigured => configured;
  @override
  String get supabaseUrl => 'https://x.supabase.co';
  @override
  String get supabaseAnonKey => 'anon';
}

/// Share state without Supabase: records the calls the dialogs make.
class _FakeShare extends ShareProvider {
  _FakeShare(SyncProvider sync) : super(syncProvider: sync);

  bool sharing = false;
  final Set<String> guestIds = {};
  String? controller;
  String? startedFor;
  int stops = 0;
  final List<(String, String, String)> joins = [];
  Object? joinError;

  static const code = 'A3K9PX-ABCDEFGHJKLMNPQR';

  @override
  bool get isSharing => sharing;
  @override
  String? get shareCode => sharing ? code : null;
  @override
  Set<String> get guests => guestIds;
  @override
  String? get controlledBy => controller;

  @override
  Future<String> startSharing(String sessionId) async {
    startedFor = sessionId;
    sharing = true;
    notifyListeners();
    return code;
  }

  @override
  Future<void> stopSharing() async {
    stops++;
    sharing = false;
    notifyListeners();
  }

  @override
  Future<void> grantControl(String guestId) async {
    controller = guestId;
    notifyListeners();
  }

  @override
  Future<void> revokeControl() async {
    controller = null;
    notifyListeners();
  }

  @override
  Future<void> joinSession(String c, String url, String key) async {
    joins.add((c, url, key));
    if (joinError != null) throw joinError!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSync sync;
  late _FakeShare share;
  late List<MethodCall> platformCalls;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sync = _FakeSync();
    share = _FakeShare(sync);
    platformCalls = [];
  });

  tearDown(() {
    share.dispose();
    sync.dispose();
  });

  /// A button that opens [dialog] with [showYsDialog], like MainScreen does.
  Widget harness(Widget dialog) => MultiProvider(
    providers: [
      ChangeNotifierProvider<SyncProvider>.value(value: sync),
      ChangeNotifierProvider<ShareProvider>.value(value: share),
    ],
    child: ysTestApp(
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showYsDialog(context, builder: (_) => dialog),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester, Widget dialog) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    await tester.pumpWidget(harness(dialog));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('ShareSessionDialog', () {
    testWidgets('start view: explains sharing and starts it', (tester) async {
      await open(tester, const ShareSessionDialog(sessionId: 's1'));

      expect(find.text('Share Terminal'), findsOneWidget);
      expect(
        find.textContaining('watch this terminal session'),
        findsOneWidget,
      );
      expect(
        find.text('Shared over TLS via your Supabase project.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Start Sharing'));
      await tester.pumpAndSettle();

      expect(share.startedFor, 's1');
      expect(find.text('Sharing Live'), findsOneWidget);
      expect(find.text(_FakeShare.code), findsOneWidget);
      expect(find.text('0 viewers'), findsOneWidget);
      expect(find.text('Tap code to copy'), findsOneWidget);
    });

    testWidgets('tapping the code copies it and toasts', (tester) async {
      share.sharing = true;
      await open(tester, const ShareSessionDialog(sessionId: 's1'));

      await tester.tap(find.text(_FakeShare.code));
      await tester.pump();

      final copy = platformCalls
          .where((c) => c.method == 'Clipboard.setData')
          .toList();
      expect(copy, isNotEmpty);
      expect((copy.last.arguments as Map)['text'], _FakeShare.code);
      expect(find.text('Code copied'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('grant, then revoke control', (tester) async {
      share
        ..sharing = true
        ..guestIds.add('guest-1234567890');
      await open(tester, const ShareSessionDialog(sessionId: 's1'));

      expect(find.text('1 viewer'), findsOneWidget);
      expect(find.text('Grant control'), findsOneWidget);
      expect(find.text('guest-12'), findsOneWidget);

      await tester.tap(find.text('Grant'));
      await tester.pumpAndSettle();
      expect(share.controller, 'guest-1234567890');
      expect(find.text('Control granted'), findsOneWidget);

      await tester.tap(find.text('Revoke'));
      await tester.pumpAndSettle();
      expect(share.controller, isNull);
      expect(find.text('Grant control'), findsOneWidget);
    });

    testWidgets('Stop Sharing stops and closes the dialog', (tester) async {
      share.sharing = true;
      await open(tester, const ShareSessionDialog(sessionId: 's1'));

      await tester.tap(find.text('Stop Sharing'));
      await tester.pumpAndSettle();

      expect(share.stops, 1);
      expect(find.byType(ShareSessionDialog), findsNothing);
    });
  });

  group('JoinShareDialog', () {
    final codeField = find.byKey(const Key('join-share-code'));

    testWidgets('smoke: title, focused code field and Join', (tester) async {
      await open(tester, const JoinShareDialog());

      expect(find.text('Join Shared Session'), findsOneWidget);
      expect(find.text('Join'), findsOneWidget);
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(
        editable.focusNode.hasFocus,
        isTrue,
        reason: 'the code field is focused on open',
      );
    });

    testWidgets('typing is filtered and upper-cased', (tester) async {
      await open(tester, const JoinShareDialog());

      await tester.enterText(codeField, 'ab3k9p-x!y_z');
      await tester.pump();

      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: codeField,
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        'AB3K9P-XYZ',
      );
    });

    testWidgets('Enter on an incomplete code shows the format error', (
      tester,
    ) async {
      await open(tester, const JoinShareDialog());

      await tester.enterText(codeField, 'ABC');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle(); // the field's error animates in

      expect(
        find.text('Enter the full share code (XXXXXX-XXXXXXXXXXXXXXXX)'),
        findsOneWidget,
      );
      expect(share.joins, isEmpty);
    });

    testWidgets('without Supabase it asks to configure it first', (
      tester,
    ) async {
      sync.configured = false;
      await open(tester, const JoinShareDialog());

      await tester.enterText(codeField, _FakeShare.code);
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();

      expect(
        find.text('Configure Supabase first (Settings → Sync)'),
        findsOneWidget,
      );
      expect(share.joins, isEmpty);
    });

    testWidgets('a valid code joins and closes the dialog', (tester) async {
      await open(tester, const JoinShareDialog());

      await tester.enterText(codeField, _FakeShare.code.toLowerCase());
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();

      expect(share.joins, [
        (
          ShareCrypto.normalizeCode(_FakeShare.code)!,
          'https://x.supabase.co',
          'anon',
        ),
      ]);
      expect(find.byType(JoinShareDialog), findsNothing);
    });

    testWidgets('a failed join shows the error and re-enables Join', (
      tester,
    ) async {
      share.joinError = 'channel refused';
      await open(tester, const JoinShareDialog());

      await tester.enterText(codeField, _FakeShare.code);
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();

      expect(find.text('channel refused'), findsOneWidget);
      expect(find.byType(JoinShareDialog), findsOneWidget);
      final join = tester.widget<FButton>(
        find.ancestor(of: find.text('Join'), matching: find.byType(FButton)),
      );
      expect(join.onPress, isNotNull);
    });
  });
}
