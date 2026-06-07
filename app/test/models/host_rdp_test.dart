import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';

void main() {
  test('Host JSON round-trips protocol, domain, rdpSecurity', () {
    final h = Host(
      label: 'win',
      host: '10.0.0.5',
      port: 3389,
      username: 'admin',
      authType: AuthType.password,
      protocol: HostProtocol.rdp,
      domain: 'CORP',
      rdpSecurity: RdpSecurityMode.nla,
    );
    final back = Host.fromJson(h.toJson());
    expect(back.protocol, HostProtocol.rdp);
    expect(back.domain, 'CORP');
    expect(back.rdpSecurity, RdpSecurityMode.nla);
  });

  test('legacy JSON without protocol parses as ssh', () {
    final back = Host.fromJson({
      'id': 'y',
      'label': 'l',
      'host': 'h',
      'port': 22,
      'username': 'u',
      'authType': 'password',
    });
    expect(back.protocol, HostProtocol.ssh);
    expect(back.domain, isNull);
    expect(back.rdpSecurity, RdpSecurityMode.auto);
  });

  test('copyWith carries over RDP fields', () {
    final h = Host(
      label: 'w',
      host: '1.2.3.4',
      port: 3389,
      username: 'u',
      protocol: HostProtocol.rdp,
      domain: 'DOM',
      rdpSecurity: RdpSecurityMode.tls,
    );
    final c = h.copyWith(rdpSecurity: RdpSecurityMode.auto);
    expect(c.protocol, HostProtocol.rdp);
    expect(c.domain, 'DOM');
    expect(c.rdpSecurity, RdpSecurityMode.auto);
  });
}
