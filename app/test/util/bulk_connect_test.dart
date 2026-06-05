import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/util/bulk_connect.dart';

void main() {
  test('splits selection into to-connect and skipped', () {
    final a = Host(label: 'a', host: 'a.x', username: 'u');
    final b = Host(label: 'b', host: 'b.x', username: 'u');
    final c = Host(label: 'c', host: 'c.x', username: 'u');
    final plan =
        planConnectAll(selected: [a, b, c], liveHostIds: {b.id});
    expect(plan.toConnect.map((h) => h.label).toList(), ['a', 'c']);
    expect(plan.skipped, 1);
  });

  test('nothing live connects everything', () {
    final a = Host(label: 'a', host: 'a.x', username: 'u');
    final plan = planConnectAll(selected: [a], liveHostIds: {});
    expect(plan.toConnect, hasLength(1));
    expect(plan.skipped, 0);
  });
}
