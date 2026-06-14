import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/shell_integration_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';

String b64(String s) => base64.encode(utf8.encode(s));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('code 52 with osc52 on writes decoded text to the clipboard', () {
    final svc = SshService(StorageService());
    final written = <String>[];
    svc.clipboardWriter = (t) async => written.add(t);

    svc.dispatchPrivateOsc('52', ['c', b64('copied!')],
        osc52On: true, siOn: false, sessionId: 's1', absoluteCursorY: 0);

    expect(written, ['copied!']);
  });

  test('code 52 with osc52 off does not write', () {
    final svc = SshService(StorageService());
    final written = <String>[];
    svc.clipboardWriter = (t) async => written.add(t);

    svc.dispatchPrivateOsc('52', ['c', b64('nope')],
        osc52On: false, siOn: false, sessionId: 's1', absoluteCursorY: 0);

    expect(written, isEmpty);
  });

  test('OSC 52 read query is never written', () {
    final svc = SshService(StorageService());
    final written = <String>[];
    svc.clipboardWriter = (t) async => written.add(t);

    svc.dispatchPrivateOsc('52', ['c', '?'],
        osc52On: true, siOn: false, sessionId: 's1', absoluteCursorY: 0);

    expect(written, isEmpty);
  });

  test('code 7 routes to shell integration (cwd), not the clipboard', () {
    final si = ShellIntegrationProvider();
    final svc = SshService(StorageService(), shellIntegration: si);
    final written = <String>[];
    svc.clipboardWriter = (t) async => written.add(t);

    svc.dispatchPrivateOsc('7', ['file://host/home/user'],
        osc52On: true, siOn: true, sessionId: 's1', absoluteCursorY: 0);

    expect(written, isEmpty);
    expect(si.cwdFor('s1'), '/home/user');
  });
}
