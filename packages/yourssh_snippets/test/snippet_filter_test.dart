import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';

void main() {
  final snippets = [
    Snippet(label: 'Restart nginx', command: 'systemctl restart nginx'),
    Snippet(label: 'Disk usage', command: 'df -h', tag: 'Monitoring'),
    Snippet(label: 'Tail syslog', command: 'tail -f /var/log/syslog'),
  ];

  test('empty query returns the full list', () {
    expect(filterSnippets(snippets, ''), snippets);
  });

  test('matches label case-insensitively', () {
    final hits = filterSnippets(snippets, 'RESTART');
    expect(hits.map((s) => s.label), ['Restart nginx']);
  });

  test('matches command text', () {
    final hits = filterSnippets(snippets, 'df -h');
    expect(hits.map((s) => s.label), ['Disk usage']);
  });

  test('matches tag case-insensitively', () {
    final hits = filterSnippets(snippets, 'monitor');
    expect(hits.map((s) => s.label), ['Disk usage']);
  });

  test('no match returns empty list', () {
    expect(filterSnippets(snippets, 'kubernetes'), isEmpty);
  });
}
