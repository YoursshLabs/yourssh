import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/cli/host_resolver.dart';

Host h(String label, {String? id, String user = 'u', String host = 'h', int port = 22}) =>
    Host(id: id, label: label, host: host, username: user, port: port);

void main() {
  test('id match wins over a label equal to another host id', () {
    final a = h('a', id: 'x1');
    final b = h('x1', id: 'b');
    final r = resolveHost('x1', [b, a], allowAdHoc: false);
    expect((r as ResolvedHost).host, same(a));
  });

  test('label is case-insensitive and trimmed', () {
    final a = h('prod db');
    final r = resolveHost('  Prod DB ', [a], allowAdHoc: false);
    expect((r as ResolvedHost).host, same(a));
  });

  test('NFD query matches NFC label', () {
    final a = h('K\u1EBFt n\u1ED1i'); // "Kết nối" precomposed
    final r = resolveHost('Ke\u0302\u0301t no\u0302\u0301i', [a], allowAdHoc: false);
    expect((r as ResolvedHost).host, same(a));
  });

  test('two same labels are ambiguous', () {
    final a = h('web'), b = h('web');
    final r = resolveHost('web', [a, b], allowAdHoc: false);
    expect((r as AmbiguousHost).candidates, [a, b]);
  });

  test('user@host:port matches saved host', () {
    final a = h('x', user: 'root', host: '10.0.0.5', port: 2222);
    final r = resolveHost('root@10.0.0.5:2222', [a], allowAdHoc: false);
    expect((r as ResolvedHost).host, same(a));
  });

  test('ad hoc when allowed, unknown otherwise', () {
    final r = resolveHost('root@10.0.0.5:2222', [], allowAdHoc: true);
    final t = r as AdHocTarget;
    expect([t.user, t.hostname, t.port], ['root', '10.0.0.5', 2222]);
    expect(resolveHost('root@10.0.0.5:2222', [], allowAdHoc: false), isA<UnknownHost>());
    expect(resolveHost('nope', [], allowAdHoc: true), isA<UnknownHost>());
  });

  test('ad hoc user or host starting with a dash is unknown', () {
    expect(resolveHost('-oProxyCommand=x@h', [], allowAdHoc: true), isA<UnknownHost>());
    expect(resolveHost('u@-h', [], allowAdHoc: true), isA<UnknownHost>());
    expect(resolveHost('-u@h:22', [], allowAdHoc: true), isA<UnknownHost>());
  });

  test('ad hoc rejects whitespace, control chars and odd users/hosts', () {
    for (final q in ['a b@h', 'u@h\nx', 'u@h x', 'u@h_x', 'u\n@h', 'u@']) {
      expect(resolveHost(q, [], allowAdHoc: true), isA<UnknownHost>(), reason: q);
    }
  });

  test('ad hoc accepts bracketed IPv6 and dotted users', () {
    final t = resolveHost('u@[::1]:22', [], allowAdHoc: true) as AdHocTarget;
    expect([t.user, t.hostname, t.port], ['u', '::1', 22]);
    final d = resolveHost('first.last@Host-1.example.com', [], allowAdHoc: true)
        as AdHocTarget;
    expect(d.hostname, 'Host-1.example.com');
  });
}
