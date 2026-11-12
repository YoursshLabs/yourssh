import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/rdp_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/audit_service.dart';
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

  test('first-use verifier error after the tab closed: no audit row, no notify',
      () async {
    final audit = AuditService()..initInMemory();
    p.audit = audit;
    p.rdpPinLookup = (_, _) => null;
    final gate = Completer<bool>();
    p.rdpCertVerifier = (_, _, _) => gate.future;
    final s = (await p.connectRdp(_host()))!;
    // No native lib under test: the tab starts in error; put it in the
    // connecting state a real probe is in so a failure would be audited.
    s.status = RdpSessionStatus.connecting;
    s.notifyState();
    final ev = StreamController<frb.RdpEvent>();
    s.attach(ev.stream);
    ev.add(const frb.RdpEvent.certMismatch(fingerprint: 'real-fp'));
    await pump();

    p.closeSession(s.id); // tab closed while the prompt is pending
    var notified = 0;
    p.addListener(() => notified++);
    gate.completeError(StateError('dialog failed'));
    await pump();

    expect(audit.query(const AuditFilter(type: 'connect')), isEmpty);
    expect(notified, 0);
    audit.dispose();
  });

  test('CLI-initiated RDP audit rows carry via: cli, source stays rdp',
      () async {
    final audit = AuditService()..initInMemory();
    p.audit = audit;
    p.rdpPinLookup = (_, _) => null; // no cert callback -> straight to connected
    final s = (await p.connectAny(_host(), auditSource: 'cli'))! as RdpSession;
    final ev = StreamController<frb.RdpEvent>();
    s.attach(ev.stream);
    ev.add(const frb.RdpEvent.started(sessionId: 1));
    ev.add(frb.RdpEvent.connected(
        cert: const frb.RdpCertInfo(sha256Fingerprint: 'ab', subject: 's'),
        desktopWidth: 800,
        desktopHeight: 600));
    ev.add(const frb.RdpEvent.disconnected(reason: 'bye'));
    await pump();

    // (No native lib in unit tests: the session starts in `error`, so the
    // connect row is not reachable here; the disconnect row shares the same
    // `via` mapping.)
    final rows = audit.query(const AuditFilter(type: 'disconnect'));
    expect(rows.length, 1);
    expect(rows.single.meta['source'], 'rdp');
    expect(rows.single.meta['via'], 'cli');
    audit.dispose();
  });

  test('app-initiated RDP rows carry no via', () async {
    final audit = AuditService()..initInMemory();
    p.audit = audit;
    p.rdpPinLookup = (_, _) => null;
    final s = (await p.connectAny(_host()))! as RdpSession;
    final ev = StreamController<frb.RdpEvent>();
    s.attach(ev.stream);
    ev.add(const frb.RdpEvent.started(sessionId: 1));
    ev.add(frb.RdpEvent.connected(
        cert: const frb.RdpCertInfo(sha256Fingerprint: 'ab', subject: 's'),
        desktopWidth: 800,
        desktopHeight: 600));
    ev.add(const frb.RdpEvent.disconnected(reason: 'bye'));
    await pump();

    final rows = audit.query(const AuditFilter(type: 'disconnect'));
    expect(rows.single.meta['source'], 'rdp');
    expect(rows.single.meta.containsKey('via'), isFalse);
    audit.dispose();
  });
}
