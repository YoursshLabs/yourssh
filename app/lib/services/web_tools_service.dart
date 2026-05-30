import '../models/host.dart';
import '../models/tool_result.dart';
import 'ssh_service.dart';

class WebToolsService {
  final SshService _sshService;

  WebToolsService(this._sshService);

  /// POSIX single-quote escape: wraps in `'…'` and rewrites embedded `'` as
  /// `'\''`. Always use this for any user-supplied value interpolated into a
  /// remote shell command — including URL targets, headers, paths.
  static String shellQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";

  Future<ToolResult> run(Host host, String command) async {
    final sw = Stopwatch()..start();
    try {
      final result = await _sshService.exec(host, command);
      sw.stop();
      final output = result.stdout.isNotEmpty ? result.stdout : result.stderr;
      return ToolResult.success(output: output, durationMs: sw.elapsedMilliseconds);
    } catch (e) {
      return ToolResult.failure(error: e.toString());
    }
  }

  Future<ToolResult> ping(Host host, String target, {int count = 4}) =>
      run(host, buildPingCommand(target, count: count));

  Future<ToolResult> curl(Host host, String url, {
    String method = 'GET',
    Map<String, String> headers = const {},
    String? body,
  }) =>
      run(host, buildCurlCommand(url, method: method, headers: headers, body: body));

  Future<ToolResult> dnsLookup(Host host, String target, {String type = 'A'}) =>
      run(host, buildDnsLookupCommand(target, type: type));

  Future<ToolResult> traceroute(Host host, String target) =>
      run(host, buildTracerouteCommand(target));

  Future<ToolResult> portScan(Host host, String target,
          {List<int> ports = const [22, 80, 443, 3306, 5432, 6379, 8080, 8443]}) =>
      run(host, buildPortScanCommand(target, ports: ports));

  Future<ToolResult> whois(Host host, String target) =>
      run(host, 'whois ${shellQuote(target)} 2>&1');

  Future<ToolResult> netstat(Host host) =>
      run(host, 'ss -tulpn 2>&1 || netstat -tulpn 2>&1');

  Future<ToolResult> diskUsage(Host host, String path) =>
      run(host, 'df -h ${shellQuote(path)} 2>&1');

  Future<ToolResult> topProcesses(Host host) =>
      run(host, 'ps aux --sort=-%cpu 2>&1 | head -20');

  Future<ToolResult> memoryInfo(Host host) =>
      run(host, 'free -h 2>&1 || vm_stat 2>&1');

  Future<ToolResult> httpHeaders(Host host, String url) =>
      run(host, 'curl -sI ${shellQuote(url)} 2>&1');

  Future<ToolResult> sslCert(Host host, String target, {int port = 443}) {
    final t = shellQuote(target);
    return run(
      host,
      'echo | openssl s_client -connect $t:$port -servername $t 2>&1 | openssl x509 -noout -text 2>&1 | head -40',
    );
  }

  // Static command builders (tested in isolation)

  static String buildPingCommand(String host, {int count = 4}) =>
      'ping -c $count ${shellQuote(host)} 2>&1';

  static String buildCurlCommand(
    String url, {
    String method = 'GET',
    Map<String, String> headers = const {},
    String? body,
  }) {
    final parts = <String>[
      'curl',
      '-s',
      '-w',
      shellQuote(r'\n---\nHTTP Status: %{http_code}\nTime: %{time_total}s'),
      '-X',
      shellQuote(method),
    ];
    for (final h in headers.entries) {
      parts.add('-H');
      parts.add(shellQuote('${h.key}: ${h.value}'));
    }
    if (body != null) {
      parts.add('-d');
      parts.add(shellQuote(body));
    }
    parts.add(shellQuote(url));
    parts.add('2>&1');
    return parts.join(' ');
  }

  static String buildDnsLookupCommand(String host, {String type = 'A'}) {
    final h = shellQuote(host);
    final t = shellQuote(type);
    return 'dig $h $t 2>&1 || nslookup $h 2>&1';
  }

  static String buildTracerouteCommand(String host) {
    final h = shellQuote(host);
    return 'traceroute $h 2>&1 || tracepath $h 2>&1';
  }

  static String buildPortScanCommand(String host, {List<int> ports = const [80, 443]}) {
    final h = shellQuote(host);
    final p = ports.join(' ');
    return 'nc -zv $h $p 2>&1 || '
        'for port in $p; do (echo >/dev/tcp/$h/\$port) 2>/dev/null && echo "Port \$port: open" || echo "Port \$port: closed"; done 2>&1';
  }
}
