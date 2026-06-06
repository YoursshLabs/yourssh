import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/util/host_sort.dart';

Host _host(String label, {String host = '1.1.1.1', DateTime? created}) => Host(
      label: label,
      host: host,
      username: 'root',
      createdAt: created,
    );

void main() {
  group('HostSortMode.fromKey', () {
    test('maps every key to its mode', () {
      for (final mode in HostSortMode.values) {
        expect(HostSortMode.fromKey(mode.key), mode);
      }
    });

    test('falls back to nameAsc on unknown or null', () {
      expect(HostSortMode.fromKey('bogus'), HostSortMode.nameAsc);
      expect(HostSortMode.fromKey(null), HostSortMode.nameAsc);
    });
  });

  group('sortHosts', () {
    test('nameAsc sorts case-insensitively', () {
      final sorted = sortHosts(
          [_host('zeta'), _host('Alpha'), _host('beta')], HostSortMode.nameAsc);
      expect(sorted.map((h) => h.label).toList(), ['Alpha', 'beta', 'zeta']);
    });

    test('nameDesc reverses nameAsc', () {
      final sorted = sortHosts(
          [_host('Alpha'), _host('zeta'), _host('beta')], HostSortMode.nameDesc);
      expect(sorted.map((h) => h.label).toList(), ['zeta', 'beta', 'Alpha']);
    });

    test('createdDesc puts newest first, createdAsc oldest first', () {
      final old = _host('old', created: DateTime(2024, 1, 1));
      final mid = _host('mid', created: DateTime(2025, 6, 1));
      final newest = _host('new', created: DateTime(2026, 1, 1));
      expect(sortHosts([mid, newest, old], HostSortMode.createdDesc),
          [newest, mid, old]);
      expect(sortHosts([mid, newest, old], HostSortMode.createdAsc),
          [old, mid, newest]);
    });

    test('hostAsc sorts by hostname case-insensitively', () {
      final a = _host('x', host: 'Beta.example.com');
      final b = _host('y', host: 'alpha.example.com');
      expect(sortHosts([a, b], HostSortMode.hostAsc), [b, a]);
      expect(sortHosts([a, b], HostSortMode.hostDesc), [a, b]);
    });

    test('equal keys tie-break by label then id (deterministic)', () {
      final a = _host('same', host: '9.9.9.9');
      final b = _host('same', host: '9.9.9.9');
      final expected = a.id.compareTo(b.id) < 0 ? [a, b] : [b, a];
      expect(sortHosts([a, b], HostSortMode.hostAsc), expected);
      expect(sortHosts([b, a], HostSortMode.hostAsc), expected);
    });

    test('does not mutate the input list', () {
      final input = [_host('b'), _host('a')];
      final before = List<Host>.of(input);
      sortHosts(input, HostSortMode.nameAsc);
      expect(input, before);
    });
  });
}
