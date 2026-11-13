// User-journey screenshot harness for the user docs (macOS desktop).
//
// Fully isolated: in-memory prefs + fake secure storage + fake path_provider +
// a temp HOME (see docs/isolation.dart). Build + run it through
//   tool/docs_journey.sh            (repo root)
// which launches the built binary directly with HOME=<temp demo home>.
//
// Needs the controller's demo servers (SSH 2222, bastion 2223, RDP 3389,
// VNC 5900). Output: screenshots/docs/<NN-section>/<NN-step>.png + INDEX.md.
import 'dart:io';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:yourssh/main.dart' as app;
import 'package:yourssh/mobile/mobile_app.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/known_host.dart';
import 'package:yourssh/models/ssh_key.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';

import 'docs/isolation.dart';
import 'docs/nav.dart';
import 'docs/sections.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('docs journey', timeout: const Timeout(Duration(hours: 3)),
      (tester) async {
    final out = Platform.environment['DOCS_OUT'] ?? '${Directory.current.path}/screenshots/docs';
    final wanted = (Platform.environment['DOCS_SECTIONS'] ?? '')
        .split(',')
        .where((s) => s.isNotEmpty)
        .toSet();
    final sandbox = installIsolation(prefs: {
      // Debounce the GitHub update check: no network, no banner.
      'last_update_check': DateTime.now().millisecondsSinceEpoch,
      // Bastion pre-pinned under a DIFFERENT key type with a fake fingerprint:
      // its first connect raises the "Host key type changed" dialog (section 05).
      if (!isMobileMode)
        'yourssh.known_hosts': jsonEncode([
          KnownHost(
            host: '127.0.0.1',
            port: 2223,
            keyType: 'ssh-rsa',
            fingerprint: 'SHA256:Zm9ha2UtZG9jcy1kZW1vLWZpbmdlcnByaW50LW5vdC1yZWFs',
            addedAt: DateTime(2026, 11, 1),
          ).toJson(),
        ]),
    });
    final shots = Shots(out);
    final ctx = JourneyContext(tester, shots, sandbox);
    // A framework exception (overflow, a plugin error...) must not abort the
    // whole run: log it and keep it for the report.
    FlutterError.onError = (d) {
      final msg = d.exceptionAsString().split('\n').first;
      stdout.writeln('FLUTTER ERROR: $msg');
      ctx.flutterErrors.add(msg);
    };

    if (isMobileMode) {
      await _mountMobile(sandbox);
    } else {
      app.main(const <String>[]);
    }
    await sleepPump(tester, 2500);

    try {
      for (final s in allSections) {
        if (wanted.isNotEmpty && !wanted.contains(s.id)) continue;
        stdout.writeln('=== SECTION ${s.id} ${s.name}');
        try {
          await s.run(ctx);
        } catch (e, st) {
          stdout.writeln('SECTION ${s.id} FAILED: $e\n$st');
          ctx.failures.add('${s.id} ${s.name}: $e');
          try {
            await shots.snap(tester, '${s.id}-${s.name}/ZZ-failure', 'FAILURE STATE: $e');
          } catch (_) {}
          await ctx.recover();
        }
      }
    } finally {
      await ctx.writeIndex();
      stdout.writeln('FAILURES: ${ctx.failures}');
      stdout.writeln('TOTAL SHOTS: ${shots.taken.length}');
      stdout.writeln('JOURNEY DONE');
    }
    exit(0);
  });
}

/// Phone-sized window + the mobile root, seeded with demo data (in-memory).
Future<void> _mountMobile(DocsSandbox sandbox) async {
  const pw = 'demo1234';
  final hosts = [
    Host(label: 'Demo Server', host: '127.0.0.1', port: 2222, username: 'demo',
        group: 'Lab', tags: const ['docs', 'linux'], detectedOs: 'alpine'),
    Host(label: 'Bastion', host: '127.0.0.1', port: 2223, username: 'demo',
        group: 'Lab', tags: const ['jump'], detectedOs: 'alpine'),
  ];
  final storage = StorageService();
  await storage.saveHosts(hosts);
  for (final h in hosts) {
    await storage.savePassword(h.id, pw);
  }
  final keySrc = Platform.environment['DOCS_KEY_SRC']!;
  final pubFile = File('$keySrc.pub');
  final key = SshKeyEntry(
    label: 'demo_ed25519',
    algorithm: KeyAlgorithm.ed25519,
    publicKey: pubFile.existsSync()
        ? pubFile.readAsStringSync().trim()
        : 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDemoOnlyNotARealKeyAAAAAAAAAAAAAAAAAAAA demo@docs',
    privateKeyPath: keySrc,
  );
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('yourssh.keys', jsonEncode([key.toJson()]));
  await prefs.setString(
      'yourssh.snippets',
      jsonEncode([
        Snippet(label: 'Disk usage', command: 'df -h | sort -k5 -r | head -20', description: 'Largest filesystems first', tag: 'system'),
        Snippet(label: 'Top memory', command: 'ps aux --sort=-%mem | head -15', description: 'Heaviest processes by RSS', tag: 'system'),
        Snippet(label: 'Tail logs', command: 'tail -f /var/log/messages', description: 'Follow the system log', tag: 'logs'),
      ].map((x) => x.toJson()).toList()));
  app.kAppVersion = '0.3.0';
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(300, 400));
  await windowManager.setSize(const Size(390, 876));
  await windowManager.center();
  await windowManager.setAlwaysOnTop(true);
  await windowManager.show();
  await windowManager.focus();
  runApp(const YourSSHMobileApp());
}
