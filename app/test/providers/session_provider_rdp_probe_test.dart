import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/rdp_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';
// ignore: implementation_imports
import 'package:yourssh_rdp/src/generated/api.dart' as frb;

Host _host() => Host(
    id: 'h1',
    label: 'win',
    host: '10.0.0.5',
    port: 3389,
    username: 'u',
    authType: AuthType.password,
    protocol: HostProtocol.rdp);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late SessionProvider p;
  setUp(() => p = SessionProvider(SshService(StorageService()), TabMetadataService()));
  tearDown(() => p.dispose());

  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('no pin: connectRdp passes the probe sentinel, never null', () async {
    p.rdpPinLookup = (_, _) => null;
    final s = (await p.connectRdp(_host()))!;
    expect(s.client.config.expectedFingerprint, kRdpUnpinnedProbe);
    expect(s.isFirstUseProbe, isTrue);
  });

  test('pin present: real fingerprint is passed, not a probe', () async {
    p.rdpPinLookup = (_, _) => 'aa';
    final s = (await p.connectRdp(_host()))!;
    expect(s.client.config.expectedFingerprint, 'aa');
    expect(s.isFirstUseProbe, isFalse);
  });

  test('probe certMismatch uses first-use verifier, accept reconnects with pin',
      () async {
    String? pin;
    p.rdpPinLookup = (_, _) => pin;
    final verified = <String>[];
    var mismatchCalls = 0;
    p.rdpCertVerifier = (h, port, fp) async {
      verified.add('$h:$port:$fp');
      pin = fp; // main.dart pins on accept
      return true;
    };
    p.rdpCertMismatchHandler = (h, port, fp) async {
      mismatchCalls++;
      return true;
    };
    final s = (await p.connectRdp(_host()))!;
    final ev = StreamController<frb.RdpEvent>();
    s.attach(ev.stream);
    ev.add(const frb.RdpEvent.certMismatch(fingerprint: 'real-fp'));
    await pump();

    expect(verified, ['10.0.0.5:3389:real-fp']);
    expect(mismatchCalls, 0);
    expect(p.sessions.contains(s), isFalse);
    final next = p.sessions.whereType<RdpSession>().single;
    expect(next.client.config.expectedFingerprint, 'real-fp');
    expect(next.isFirstUseProbe, isFalse);
  });

  test('probe: status is not the "changed" error while verifying', () async {
    p.rdpPinLookup = (_, _) => null;
    final gate = Completer<bool>();
    p.rdpCertVerifier = (_, _, _) => gate.future;
    final s = (await p.connectRdp(_host()))!;
    final ev = StreamController<frb.RdpEvent>();
    s.attach(ev.stream);
    ev.add(const frb.RdpEvent.certMismatch(fingerprint: 'real-fp'));
    await pump();
    expect(s.lastMessage, isNot(contains('changed')));
    expect(s.lastMessage, contains('Verifying'));
    gate.complete(false);
    await pump();
  });

  test('probe reject: no reconnect, error says not trusted', () async {
    p.rdpPinLookup = (_, _) => null;
    p.rdpCertVerifier = (_, _, _) async => false;
    final s = (await p.connectRdp(_host()))!;
    final ev = StreamController<frb.RdpEvent>();
    s.attach(ev.stream);
    ev.add(const frb.RdpEvent.certMismatch(fingerprint: 'real-fp'));
    await pump();

    expect(p.sessions.whereType<RdpSession>().single, same(s));
    expect(s.status, RdpSessionStatus.error);
    expect(s.lastMessage, contains('not trusted'));
  });

  test('no verifier wired: probe does not auto-trust or loop', () async {
    p.rdpPinLookup = (_, _) => null;
    final s = (await p.connectRdp(_host()))!;
    final ev = StreamController<frb.RdpEvent>();
    s.attach(ev.stream);
    ev.add(const frb.RdpEvent.certMismatch(fingerprint: 'real-fp'));
    await pump();
    expect(p.sessions.whereType<RdpSession>().single, same(s));
    expect(s.status, RdpSessionStatus.error);
  });

  test('real mismatch (pin existed) keeps the mismatch handler path', () async {
    p.rdpPinLookup = (_, _) => 'old';
    var verifierCalls = 0;
    p.rdpCertVerifier = (_, _, _) async {
      verifierCalls++;
      return true;
    };
    final seen = <String>[];
    p.rdpCertMismatchHandler = (h, port, fp) async {
      seen.add(fp);
      return false;
    };
    final s = (await p.connectRdp(_host()))!;
    final ev = StreamController<frb.RdpEvent>();
    s.attach(ev.stream);
    ev.add(const frb.RdpEvent.certMismatch(fingerprint: 'new'));
    await pump();
    expect(seen, ['new']);
    expect(verifierCalls, 0);
    expect(s.lastMessage, contains('changed'));
  });
}
