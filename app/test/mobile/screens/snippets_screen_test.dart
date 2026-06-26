import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';

import 'package:yourssh/mobile/screens/mobile_snippets_screen.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

// ── Fake SnippetProvider ──────────────────────────────────────────────────────

class _FakeSnippetProvider extends SnippetProvider {
  final List<Snippet> _seed;
  _FakeSnippetProvider(this._seed);

  @override
  List<Snippet> get snippets => _seed;
}

// ── Fake SshService — tracks sendInput calls ──────────────────────────────────

class _FakeSshService extends SshService {
  _FakeSshService() : super(StorageService());

  final List<({String sessionId, String text})> inputCalls = [];

  @override
  bool sendInput(String sessionId, String text) {
    inputCalls.add((sessionId: sessionId, text: text));
    return true;
  }
}

// ── Fake SessionProvider — one active SSH session ─────────────────────────────

class _FakeSessionProvider extends SessionProvider {
  final SshSession _session;

  _FakeSessionProvider(this._session)
      : super(SshService(StorageService()), TabMetadataService());

  @override
  SshSession? get activeSshSession => _session;
}

// ── Pump helper ────────────────────────────────────────────────────────────────

Future<void> _pump(
  WidgetTester tester, {
  required SnippetProvider snippetProvider,
  required SessionProvider sessionProvider,
  required SshService sshService,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SnippetProvider>.value(value: snippetProvider),
        ChangeNotifierProvider<SessionProvider>.value(value: sessionProvider),
        Provider<SshService>.value(value: sshService),
      ],
      child: MaterialApp(
        theme: buildMobileTheme(),
        home: const MobileSnippetsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late _FakeSshService fakeSsh;
  late _FakeSnippetProvider fakeSnippets;
  late _FakeSessionProvider fakeSession;
  late SshSession activeSession;

  setUp(() {
    fakeSsh = _FakeSshService();
    fakeSnippets = _FakeSnippetProvider([
      Snippet(label: 'Disk usage', command: 'df -h', tag: 'system'),
      Snippet(label: 'Tail log', command: 'tail -f /var/log/syslog', tag: 'logs'),
    ]);
    activeSession = SshSession(
      host: Host(label: 'web-01', host: '10.0.0.1', username: 'root'),
    );
    fakeSession = _FakeSessionProvider(activeSession);
  });

  testWidgets('shows "Snippets" title', (tester) async {
    await _pump(tester,
        snippetProvider: fakeSnippets,
        sessionProvider: fakeSession,
        sshService: fakeSsh);
    expect(find.text('Snippets'), findsOneWidget);
  });

  testWidgets('shows active host name in subtitle', (tester) async {
    await _pump(tester,
        snippetProvider: fakeSnippets,
        sessionProvider: fakeSession,
        sshService: fakeSsh);
    expect(find.textContaining('web-01'), findsOneWidget);
  });

  testWidgets('shows "No active session" subtitle when no session', (tester) async {
    final noSession = _FakeSessionProvider(
      SshSession(
        host: Host(label: 'dummy', host: '0.0.0.0', username: 'u'),
      ),
    );
    // Override to return null active session
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SnippetProvider>.value(value: fakeSnippets),
          ChangeNotifierProvider<SessionProvider>.value(
            value: _NullSessionProvider(),
          ),
          Provider<SshService>.value(value: fakeSsh),
        ],
        child: MaterialApp(
          theme: buildMobileTheme(),
          home: const MobileSnippetsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No active session'), findsOneWidget);
  });

  testWidgets('renders both snippet labels', (tester) async {
    await _pump(tester,
        snippetProvider: fakeSnippets,
        sessionProvider: fakeSession,
        sshService: fakeSsh);
    expect(find.text('Disk usage'), findsOneWidget);
    expect(find.text('Tail log'), findsOneWidget);
  });

  testWidgets('renders snippet commands in monospace', (tester) async {
    await _pump(tester,
        snippetProvider: fakeSnippets,
        sessionProvider: fakeSession,
        sshService: fakeSsh);
    expect(find.text('df -h'), findsOneWidget);
  });

  testWidgets('renders category filter chips (All + distinct tags)', (tester) async {
    await _pump(tester,
        snippetProvider: fakeSnippets,
        sessionProvider: fakeSession,
        sshService: fakeSsh);
    // "All" chip only appears in the filter bar
    expect(find.text('All'), findsOneWidget);
    // Tags appear in both filter chips and snippet cards (at least once each)
    expect(find.text('system'), findsAtLeastNWidgets(1));
    expect(find.text('logs'), findsAtLeastNWidgets(1));
  });

  testWidgets('tapping a snippet calls sendInput with command + newline',
      (tester) async {
    await _pump(tester,
        snippetProvider: fakeSnippets,
        sessionProvider: fakeSession,
        sshService: fakeSsh);

    await tester.tap(find.text('Disk usage'));
    await tester.pumpAndSettle();

    expect(fakeSsh.inputCalls, hasLength(1));
    expect(fakeSsh.inputCalls.first.sessionId, equals(activeSession.id));
    expect(fakeSsh.inputCalls.first.text, equals('df -h\n'));
  });

  testWidgets('tapping snippet with no active session shows snackbar',
      (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SnippetProvider>.value(value: fakeSnippets),
          ChangeNotifierProvider<SessionProvider>.value(
            value: _NullSessionProvider(),
          ),
          Provider<SshService>.value(value: fakeSsh),
        ],
        child: MaterialApp(
          theme: buildMobileTheme(),
          home: const MobileSnippetsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Disk usage'));
    await tester.pumpAndSettle();

    expect(find.text('No active session'), findsAtLeastNWidgets(1));
    expect(fakeSsh.inputCalls, isEmpty);
  });

  testWidgets('category chip filters snippets', (tester) async {
    await _pump(tester,
        snippetProvider: fakeSnippets,
        sessionProvider: fakeSession,
        sshService: fakeSsh);

    // Tap the "logs" filter chip (first occurrence is the chip in the filter bar).
    // The "logs" tag also appears in the snippet card, so we target the chip row.
    await tester.tap(find.text('logs').first);
    await tester.pumpAndSettle();

    expect(find.text('Tail log'), findsOneWidget);
    expect(find.text('Disk usage'), findsNothing);
  });
}

// ── Helper: SessionProvider with no active SSH session ───────────────────────

class _NullSessionProvider extends SessionProvider {
  _NullSessionProvider()
      : super(SshService(StorageService()), TabMetadataService());

  @override
  SshSession? get activeSshSession => null;
}
