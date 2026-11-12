import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/cli/host_summary.dart';

void main() {
  test('summary has exactly the 8 non-secret keys', () {
    final h = Host(
      label: 'l', host: 'h', username: 'u', keyId: 'secret-key',
      tags: ['t'], jumpHostIds: ['j'],
      envVars: {'TOKEN': 'x'}, startupSnippet: 'echo pw',
    );
    final s = hostSummary(h);
    expect(s.keys.toSet(), {'id', 'label', 'username', 'host', 'port', 'protocol', 'tags', 'jumpHostIds'});
    expect(s['protocol'], 'ssh');
    expect(s['tags'], ['t']);
    expect(s['jumpHostIds'], ['j']);
  });
}
