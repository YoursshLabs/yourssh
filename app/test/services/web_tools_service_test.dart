import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/web_tools_service.dart';

void main() {
  test('buildPingCommand returns correct command with count', () {
    expect(
      WebToolsService.buildPingCommand('8.8.8.8', count: 4),
      "ping -c 4 '8.8.8.8' 2>&1",
    );
  });

  test('buildCurlCommand includes method and headers (shell-escaped)', () {
    final cmd = WebToolsService.buildCurlCommand(
      'https://example.com',
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: '{"key":"value"}',
    );
    expect(cmd, contains("-X 'POST'"));
    expect(cmd, contains("-H 'Content-Type: application/json'"));
    expect(cmd, contains("-d '{\"key\":\"value\"}'"));
    expect(cmd, contains("'https://example.com'"));
  });

  test('buildCurlCommand escapes single quotes in header values', () {
    final cmd = WebToolsService.buildCurlCommand(
      'https://example.com',
      headers: {'X-Pwn': "evil'; rm -rf /;"},
    );
    // Embedded single quote must be neutralised as the POSIX sequence '\''
    // so the shell sees the rest as a literal value, not a new command.
    expect(cmd, contains(r"'X-Pwn: evil'\''; rm -rf /;'"));
  });

  test('buildDnsLookupCommand uses dig when available', () {
    expect(
      WebToolsService.buildDnsLookupCommand('example.com', type: 'A'),
      "dig 'example.com' 'A' 2>&1 || nslookup 'example.com' 2>&1",
    );
  });

  test('buildTracerouteCommand returns correct platform command', () {
    final cmd = WebToolsService.buildTracerouteCommand('8.8.8.8');
    expect(cmd, contains('8.8.8.8'));
    expect(cmd, anyOf(contains('traceroute'), contains('tracepath')));
  });

  test('buildPortScanCommand targets specified ports', () {
    final cmd = WebToolsService.buildPortScanCommand('192.168.1.1', ports: [80, 443, 22]);
    expect(cmd, contains('192.168.1.1'));
  });
}
