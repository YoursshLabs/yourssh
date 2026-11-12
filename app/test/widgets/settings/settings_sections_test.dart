import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/ai_provider_config.dart';
import 'package:yourssh/models/app_release.dart';
import 'package:yourssh/models/audit_event.dart';
import 'package:yourssh/providers/audit_provider.dart';
import 'package:yourssh/services/audit_service.dart';
import 'package:yourssh/widgets/settings/ai_providers_section.dart';
import 'package:yourssh/widgets/settings/appearance_section.dart';
import 'package:yourssh/widgets/settings/audit_section.dart';
import 'package:yourssh/widgets/settings/connection_section.dart';
import 'package:yourssh/widgets/settings/hotkeys_section.dart';
import 'package:yourssh/widgets/settings/monitoring_section.dart';
import 'package:yourssh/widgets/settings/recording_section.dart';
import 'package:yourssh/widgets/settings/security_section.dart';
import 'package:yourssh/widgets/settings/sync_section.dart';
import 'package:yourssh/widgets/settings/terminal_section.dart';
import 'package:yourssh/widgets/settings/updates_section.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import 'settings_harness.dart';

/// One smoke test per Settings section: the main controls are present and
/// one control reaches its provider setter.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final secure = FakeSecureStore();
  setUp(() {
    mockPrefs();
    secure
      ..values.clear()
      ..failWrites = false
      ..install();
  });
  tearDown(secure.uninstall);

  Finder byKey(String k) => find.byKey(ValueKey(k));

  group('Connection', () {
    testWidgets('controls present; switch and selects persist', (tester) async {
      final h = SettingsHarness();
      await h.pump(tester, const ConnectionSettingsSection());

      expect(find.text('Connection'), findsOneWidget);
      for (final label in [
        'Auto-reconnect',
        'Max reconnect attempts',
        'Keep-alive interval',
        'Tmux Integration',
        'Shell Integration',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.byType(FSwitch), findsNWidgets(3));

      expect(h.settings.autoReconnect, isTrue);
      await tapSwitch(tester, const ValueKey('settings-auto-reconnect'));
      expect(h.settings.autoReconnect, isFalse);

      await tapSwitch(tester, const ValueKey('settings-tmux'));
      expect(h.settings.tmuxEnabled, isTrue);

      await pickOption(
        tester,
        const ValueKey('settings-reconnect-attempts'),
        '5 times',
      );
      expect(h.settings.reconnectAttempts, 5);

      await pickOption(tester, const ValueKey('settings-keep-alive'), 'Off');
      expect(h.settings.keepAliveInterval, 0);
    });
  });

  group('Appearance', () {
    testWidgets('terminal appearance controls; font select persists', (
      tester,
    ) async {
      final h = SettingsHarness();
      await h.pump(tester, const AppearanceSettingsSection());

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Color theme'), findsOneWidget);
      expect(find.text('Terminal font'), findsOneWidget);
      expect(find.byType(FSlider), findsOneWidget);

      await pickOption(
        tester,
        const Key('terminal-font-select'),
        'Inconsolata for Powerline',
      );
      expect(h.settings.terminalFont, 'Inconsolata for Powerline');
    });
  });

  group('Terminal', () {
    testWidgets('TERM select, default shell, add and remove a custom shell', (
      tester,
    ) async {
      final h = SettingsHarness();
      await h.pump(tester, const TerminalSettingsSection());

      expect(find.text('Terminal emulation type'), findsOneWidget);
      expect(find.text('Default local shell'), findsOneWidget);
      expect(find.text('Platform default'), findsOneWidget);

      await pickOption(tester, const ValueKey('settings-term-type'), 'vt100');
      expect(h.settings.terminalType, 'vt100');

      await tester.tap(byKey('settings-add-custom-shell'));
      await tester.pumpAndSettle();
      expect(find.text('Add custom shell'), findsOneWidget);
      expect(
        find.text('Space-separated; quoting not supported'),
        findsOneWidget,
      );
      await tester.enterText(byKey('custom-shell-name'), 'Fish');
      await tester.enterText(byKey('custom-shell-exe'), '/opt/bin/fish');
      await tester.enterText(byKey('custom-shell-args'), '-l  -i');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(h.settings.customShellProfiles, hasLength(1));
      final shell = h.settings.customShellProfiles.single;
      expect(shell.name, 'Fish');
      expect(shell.executable, '/opt/bin/fish');
      expect(shell.args, ['-l', '-i']);
      expect(find.text('/opt/bin/fish -l -i'), findsOneWidget);

      await tester.tap(byKey('settings-remove-shell-${shell.id}'));
      await tester.pumpAndSettle();
      expect(h.settings.customShellProfiles, isEmpty);
    });

    testWidgets('remove icon carries its tooltip', (tester) async {
      mockPrefs({
        'customShellProfiles': jsonEncode([
          {
            'id': 'custom-1',
            'name': 'Nu',
            'executable': '/bin/nu',
            'isCustom': true,
          },
        ]),
      });
      final h = SettingsHarness();
      await h.pump(tester, const TerminalSettingsSection());
      expect(find.byTooltip('Remove custom shell'), findsOneWidget);
    });
  });

  group('Recording', () {
    testWidgets('path, Change… and the redaction switch', (tester) async {
      mockPrefs({'recordingPath': '/tmp/casts'});
      final h = SettingsHarness();
      await h.pump(tester, const RecordingSettingsSection());

      expect(find.text('Recording path'), findsOneWidget);
      expect(find.text('/tmp/casts'), findsOneWidget);
      expect(byKey('settings-recording-change'), findsOneWidget);
      expect(find.text('Redact secrets in recordings'), findsOneWidget);
      expect(
        find.text(
          'Mask passwords/tokens (AuditRedactor patterns) before writing '
          '.cast — replay timing becomes per-line; per-host opt-out in the '
          'host panel',
        ),
        findsOneWidget,
      );

      expect(h.settings.recordingRedactionEnabled, isTrue);
      await tapSwitch(tester, const ValueKey('settings-recording-redaction'));
      expect(h.settings.recordingRedactionEnabled, isFalse);
    });
  });

  group('Monitoring', () {
    testWidgets('both switches persist', (tester) async {
      final h = SettingsHarness();
      await h.pump(tester, const MonitoringSettingsSection());

      expect(find.text('Network Stats Monitor'), findsOneWidget);
      expect(find.text('Command finish notification'), findsOneWidget);

      await tapSwitch(tester, const ValueKey('settings-network-stats'));
      expect(h.settings.networkStatsEnabled, isTrue);

      await tapSwitch(tester, const ValueKey('settings-command-notifications'));
      expect(h.settings.commandNotificationsEnabled, isTrue);
    });
  });

  group('Audit', () {
    late AuditService svc;
    late AuditProvider audit;
    setUp(() {
      svc = AuditService()..initInMemory();
      svc.record(
        AuditEvent(
          ts: DateTime(2026, 1, 1),
          type: AuditEventType.exec,
          hostId: 'h1',
          hostLabel: 'alpha',
          command: 'ls',
        ),
      );
      audit = AuditProvider(svc)..refresh();
    });
    tearDown(() {
      audit.dispose();
      svc.dispose();
    });

    testWidgets('retention select persists', (tester) async {
      final h = SettingsHarness(audit: audit);
      await h.pump(tester, const AuditSettingsSection());

      expect(find.text('Retention'), findsOneWidget);
      expect(find.text('90 days'), findsOneWidget);
      await pickOption(
        tester,
        const ValueKey('settings-audit-retention'),
        'Keep forever',
      );
      expect(h.settings.auditRetentionDays, 0);
    });

    testWidgets('Clear asks first (Cancel focused), then clears', (
      tester,
    ) async {
      final h = SettingsHarness(audit: audit);
      await h.pump(tester, const AuditSettingsSection());

      await tester.tap(byKey('settings-audit-clear'));
      await tester.pumpAndSettle();
      expect(find.text('Clear audit log?'), findsOneWidget);
      expect(find.text('All recorded events will be deleted.'), findsOneWidget);
      final cancel = tester.widget<FButton>(
        find.ancestor(of: find.text('Cancel'), matching: find.byType(FButton)),
      );
      expect(cancel.autofocus, isTrue, reason: 'safe choice holds focus');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(svc.query(const AuditFilter()).length, 1);

      await tester.tap(byKey('settings-audit-clear'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear').last);
      await tester.pumpAndSettle();
      expect(svc.query(const AuditFilter()).length, 0);
    });
  });

  group('Security', () {
    String store() => Platform.isMacOS
        ? 'macOS Keychain'
        : Platform.isWindows
        ? 'Windows Credential Manager'
        : 'system keyring';

    testWidgets('all secrets encrypted', (tester) async {
      final h = SettingsHarness();
      await h.pump(tester, const SecuritySettingsSection());

      expect(find.text('Security'), findsOneWidget);
      expect(find.text('Credential storage'), findsOneWidget);
      expect(
        find.text(
          'Host passwords, sudo passwords and key passphrases are kept in '
          'the ${store()}',
        ),
        findsOneWidget,
      );
      expect(find.text('Encrypted'), findsOneWidget);
      expect(byKey('settings-secrets-retry'), findsNothing);
    });

    testWidgets('plaintext fallback is shown and Retry moves it', (
      tester,
    ) async {
      final h = SettingsHarness();
      secure.failWrites = true;
      await tester.runAsync(() => h.storage.savePassword('h1', 'pw'));
      await h.pump(tester, const SecuritySettingsSection());

      expect(find.text('Plain text'), findsOneWidget);
      expect(
        find.text('1 credential(s) stored without encryption'),
        findsOneWidget,
      );
      expect(
        find.text(
          'The system keychain refused these, so they were written to the '
          'app preferences file as readable text — anything that can read '
          'your user account can read them.',
        ),
        findsOneWidget,
      );

      secure.failWrites = false;
      await tester.tap(byKey('settings-secrets-retry'));
      await tester.pumpAndSettle();
      expect(h.storage.plaintextSecretKeys, isEmpty);
      expect(find.text('Encrypted'), findsOneWidget);
      expect(
        find.text('Moved 1 credential(s) into the ${store()}.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('Sync', () {
    testWidgets(
      'cloud tab: fields obscured, reveal toggles, empty test errors',
      (tester) async {
        final h = SettingsHarness();
        await h.pump(tester, const SyncSettingsSection());

        expect(find.text('Sync'), findsOneWidget);
        expect(find.text('Cloud Sync'), findsOneWidget);
        expect(find.text('P2P Transfer'), findsOneWidget);
        expect(find.text('Supabase Backend'), findsOneWidget);
        expect(byKey('sync-url-field'), findsOneWidget);
        expect(
          editableIn(tester, const ValueKey('sync-anon-key-field')).obscureText,
          isTrue,
        );

        await tester.tap(find.byTooltip('Show anon key'));
        await tester.pumpAndSettle();
        expect(
          editableIn(tester, const ValueKey('sync-anon-key-field')).obscureText,
          isFalse,
        );

        await tester.tap(byKey('sync-save-test'));
        await tester.pumpAndSettle();
        expect(find.text('URL and Anon key are required'), findsOneWidget);
        expect(h.sync.isSupabaseConfigured, isFalse);
      },
    );

    testWidgets('P2P tab shows the QR export and code import actions', (
      tester,
    ) async {
      final h = SettingsHarness();
      await h.pump(tester, const SyncSettingsSection());

      await tester.tap(find.text('P2P Transfer'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Transfer all hosts and passwords to another device over LAN or '
          'Tailscale. No cloud required.',
        ),
        findsOneWidget,
      );
      expect(byKey('sync-show-qr'), findsOneWidget);
      expect(byKey('sync-import-code'), findsOneWidget);
      expect(find.text('Show QR Code'), findsOneWidget);
      expect(find.text('Import via Code'), findsOneWidget);
    });

    testWidgets('configured: sync code obscured; Regenerate confirms first', (
      tester,
    ) async {
      mockPrefs({
        'supabase_url': 'https://abc.supabase.co',
        'supabase_anon_key': 'anon',
      });
      secure.values['sync_code'] = 'ABCDEFGHJKMN';
      final h = SettingsHarness();
      await h.pump(tester, const SyncSettingsSection());

      expect(h.sync.hasSyncCode, isTrue);
      expect(find.text('Connected'), findsOneWidget);
      expect(byKey('sync-disconnect'), findsOneWidget);
      expect(find.text('Sync code'), findsOneWidget);
      expect(
        find.text(
          'This 12-character code is the only key to your synced data. '
          'Enter it on another device to join.',
        ),
        findsOneWidget,
      );
      expect(
        editableIn(tester, const ValueKey('sync-code-field')).obscureText,
        isTrue,
      );
      expect(find.byTooltip('Copy'), findsOneWidget);

      await tester.tap(find.text('Regenerate'));
      await tester.pumpAndSettle();
      expect(find.text('Regenerate sync code?'), findsOneWidget);
      expect(
        find.text(
          'A new code creates a new cloud record. Data tied to the old code '
          'becomes unreachable until you re-enter the old code.',
        ),
        findsOneWidget,
      );
      final cancel = tester.widget<FButton>(
        find.ancestor(of: find.text('Cancel'), matching: find.byType(FButton)),
      );
      expect(cancel.autofocus, isTrue);
      final confirm = tester.widget<FButton>(
        find.ancestor(
          of: find.text('Regenerate').last,
          matching: find.byType(FButton),
        ),
      );
      expect(confirm.variant, FButtonVariant.destructive);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.sync.syncCode, 'ABCDEFGHJKMN', reason: 'cancel keeps the code');
    });
  });

  group('AI providers', () {
    testWidgets('a card per provider; key saved on submit, model persists', (
      tester,
    ) async {
      final h = SettingsHarness();
      await h.pump(tester, const AiProvidersSettingsSection());

      expect(find.text('AI providers'), findsOneWidget);
      for (final label in ['Anthropic', 'OpenAI', 'Google Gemini']) {
        expect(find.text(label), findsOneWidget);
      }
      for (final p in AiProvider.values) {
        expect(
          editableIn(tester, ValueKey('ai-key-${p.name}')).obscureText,
          isTrue,
          reason: 'API keys are never shown in clear by default',
        );
      }

      await tester.enterText(byKey('ai-key-anthropic'), 'sk-ant-test');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(h.ai.configs[AiProvider.anthropic]?.apiKey, 'sk-ant-test');
      expect(find.byTooltip('Clear API key'), findsOneWidget);

      await pickOption(
        tester,
        const ValueKey('ai-model-anthropic'),
        'claude-opus-4-7',
      );
      expect(h.ai.configs[AiProvider.anthropic]?.model, 'claude-opus-4-7');

      await tester.tap(find.byTooltip('Clear API key'));
      await tester.pumpAndSettle();
      expect(h.ai.configs[AiProvider.anthropic], isNull);
    });
  });

  group('Keyboard', () {
    testWidgets('Configure opens the shortcut editor', (tester) async {
      final h = SettingsHarness();
      await h.pump(tester, const HotkeysSettingsSection());

      expect(find.text('Keyboard'), findsOneWidget);
      expect(find.text('Keyboard Shortcuts'), findsOneWidget);
      await tester.tap(byKey('settings-hotkeys-configure'));
      await tester.pumpAndSettle();
      expect(find.text('Command Palette'), findsOneWidget);
    });
  });

  group('Updates', () {
    testWidgets('version, manual check reports up to date', (tester) async {
      final h = SettingsHarness();
      await h.pump(tester, const UpdatesSettingsSection());

      expect(find.text('Updates'), findsOneWidget);
      expect(find.text('Current version'), findsOneWidget);
      expect(find.text('v0.1.34'), findsOneWidget);
      expect(
        find.text('Click "Check for updates" to look for a new version'),
        findsOneWidget,
      );
      expect(byKey('update-install'), findsNothing);

      await tester.tap(byKey('update-check'));
      await tester.pumpAndSettle();
      expect(h.update.fetches, 1);
      expect(h.updates.status, UpdateStatus.upToDate);
      expect(find.text('You are on the latest version'), findsOneWidget);
    });

    testWidgets('available: install button and release notes', (tester) async {
      final h = SettingsHarness(
        release: AppRelease.fromJson({
          'tag_name': 'v0.2.0',
          'body': 'Faster terminal',
          'assets': [],
        }),
      );
      await h.pump(tester, const UpdatesSettingsSection());
      await tester.tap(byKey('update-check'));
      await tester.pumpAndSettle();

      expect(find.text('New version v0.2.0 available'), findsOneWidget);
      expect(byKey('update-install'), findsOneWidget);
      expect(find.text('Download & install'), findsOneWidget);
      expect(find.text('Faster terminal'), findsOneWidget);
    });
  });
}
