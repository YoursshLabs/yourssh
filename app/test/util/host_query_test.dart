import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/util/host_query.dart';
import 'package:yourssh/models/host.dart';

void main() {
  group('HostQuery.parse', () {
    test('empty / whitespace query is empty', () {
      expect(HostQuery.parse('').isEmpty, isTrue);
      expect(HostQuery.parse('   ').isEmpty, isTrue);
    });

    test('key:value token becomes a facet', () {
      final q = HostQuery.parse('env:prod');
      expect(q.facets, {'env': {'prod'}});
      expect(q.terms, isEmpty);
    });

    test('same key collects multiple values', () {
      final q = HostQuery.parse('env:prod env:staging');
      expect(q.facets, {'env': {'prod', 'staging'}});
    });

    test('plain token becomes a free-text term', () {
      final q = HostQuery.parse('web');
      expect(q.terms, ['web']);
      expect(q.facets, isEmpty);
    });

    test('malformed tokens demote to free-text', () {
      final q = HostQuery.parse('env: :prod');
      expect(q.facets, isEmpty);
      expect(q.terms, ['env:', ':prod']);
    });

    test('a:b:c splits on first colon', () {
      final q = HostQuery.parse('a:b:c');
      expect(q.facets, {'a': {'b:c'}});
    });

    test('parsing is case-insensitive (lower-cased)', () {
      final q = HostQuery.parse('Env:Prod WEB');
      expect(q.facets, {'env': {'prod'}});
      expect(q.terms, ['web']);
    });
  });

  group('HostQuery.matches', () {
    Host h({String label = 'srv', String host = '10.0.0.1', String username = 'root', List<String> tags = const []}) =>
        Host(label: label, host: host, username: username, tags: tags);

    test('empty query matches everything', () {
      expect(HostQuery.parse('').matches(h()), isTrue);
    });

    test('single facet exact match', () {
      expect(HostQuery.parse('env:prod').matches(h(tags: ['env:prod'])), isTrue);
      expect(HostQuery.parse('env:prod').matches(h(tags: ['env:staging'])), isFalse);
    });

    test('same key ORs values', () {
      final q = HostQuery.parse('env:prod env:staging');
      expect(q.matches(h(tags: ['env:staging'])), isTrue);
      expect(q.matches(h(tags: ['env:dev'])), isFalse);
    });

    test('different keys AND together', () {
      final q = HostQuery.parse('env:prod role:db');
      expect(q.matches(h(tags: ['env:prod', 'role:db'])), isTrue);
      expect(q.matches(h(tags: ['env:prod'])), isFalse);
    });

    test('free-text matches label/host/username/tag-value', () {
      expect(HostQuery.parse('web').matches(h(label: 'web-1')), isTrue);
      expect(HostQuery.parse('10.0').matches(h(host: '10.0.0.5')), isTrue);
      expect(HostQuery.parse('root').matches(h(username: 'root')), isTrue);
      expect(HostQuery.parse('prod').matches(h(tags: ['env:prod'])), isTrue);
      expect(HostQuery.parse('absent').matches(h()), isFalse);
    });

    test('free-text terms AND together', () {
      expect(HostQuery.parse('web prod').matches(h(label: 'web-1', tags: ['env:prod'])), isTrue);
      expect(HostQuery.parse('web prod').matches(h(label: 'web-1')), isFalse);
    });

    test('matching is case-insensitive', () {
      expect(HostQuery.parse('ENV:PROD').matches(h(tags: ['env:prod'])), isTrue);
      expect(HostQuery.parse('WEB').matches(h(label: 'Web-1')), isTrue);
    });

    test('facet + free-text are both required', () {
      final q = HostQuery.parse('env:prod web');
      expect(q.matches(h(label: 'web-server', tags: ['env:prod'])), isTrue);
      expect(q.matches(h(label: 'web-server', tags: ['env:staging'])), isFalse);
      expect(q.matches(h(label: 'db-server', tags: ['env:prod'])), isFalse);
    });

    test('free-text matches a bare (non-facet) tag', () {
      expect(HostQuery.parse('legacy').matches(h(tags: ['legacy'])), isTrue);
    });
  });

  group('HostQuery.availableFacets', () {
    Host h(List<String> tags) => Host(label: 'l', host: 'h', username: 'u', tags: tags);

    test('returns distinct key:value tags, sorted, lower-cased', () {
      final facets = HostQuery.availableFacets([
        h(['env:prod', 'role:db']),
        h(['Env:Prod', 'plainlabel']),
        h(['region:sg']),
      ]);
      expect(facets, ['env:prod', 'region:sg', 'role:db']);
    });

    test('ignores tags without a colon', () {
      expect(HostQuery.availableFacets([h(['legacy', 'env:dev'])]), ['env:dev']);
    });
  });

  group('HostQuery.toggleToken', () {
    test('appends when absent', () {
      expect(HostQuery.toggleToken('', 'env:prod'), 'env:prod');
      expect(HostQuery.toggleToken('role:db', 'env:prod'), 'role:db env:prod');
    });

    test('removes when present (case-insensitive)', () {
      expect(HostQuery.toggleToken('env:prod role:db', 'env:prod'), 'role:db');
      expect(HostQuery.toggleToken('ENV:PROD', 'env:prod'), '');
    });
  });
}
