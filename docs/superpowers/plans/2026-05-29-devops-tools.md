# DevOps Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Web Tools suite (Ping, cURL, DNS, traceroute, whois, port scan, etc.), Cloudflare Tunnel integration, Mail Catcher, LocalShare (LAN file transfer), and Remote Terminal via tunnel.

**Architecture:** Web Tools run commands on the active SSH session via `SshService.exec()`, with results rendered in a structured UI. Cloudflare Tunnels use the `cloudflared` CLI on the remote server, managed via SSH exec. Mail Catcher is a local SMTP-to-HTTP proxy concept — runs `python3 -m smtpd` on the remote and polls via SSH. LocalShare starts an HTTP server on the local machine and shares a download link on LAN. Remote Terminal (Tunnel) uses SSH port forwarding to expose a local port.

**Tech Stack:** Flutter, `dartssh2`, `shelf` (^1.4.2, for LAN HTTP server), `network_info_plus` (^4.1.0, for LAN IP), `url_launcher` (^6.3.0)

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `app/lib/models/tool_result.dart` | Create | Structured result from a tool execution |
| `app/lib/services/web_tools_service.dart` | Create | Runs network tool commands via SSH exec |
| `app/lib/widgets/web_tools_screen.dart` | Create | Full Web Tools UI replacing placeholder |
| `app/lib/widgets/tool_result_view.dart` | Create | Formatted output display |
| `app/lib/services/cloudflare_tunnel_service.dart` | Create | Start/stop cloudflared on remote |
| `app/lib/models/tunnel_config.dart` | Create | Tunnel configuration model |
| `app/lib/providers/tunnel_provider.dart` | Create | Tunnel state management |
| `app/lib/widgets/cloudflare_tunnel_screen.dart` | Create | Tunnel management UI |
| `app/lib/services/lan_share_service.dart` | Create | Local HTTP server for LAN sharing |
| `app/lib/widgets/lan_share_screen.dart` | Create | LAN share UI |
| `app/lib/widgets/mail_catcher_screen.dart` | Create | Mail catcher UI |
| `app/lib/services/mail_catcher_service.dart` | Create | SSH-based SMTP capture |
| `app/lib/widgets/main_screen.dart` | Modify | Wire Web Tools screen, add DevOps section |
| `app/pubspec.yaml` | Modify | Add shelf, network_info_plus, url_launcher |
| `app/test/models/tool_result_test.dart` | Create | Unit tests |
| `app/test/services/web_tools_service_test.dart` | Create | Unit tests for output parsing |

---

### Task 1: Add Dependencies

**Files:**
- Modify: `app/pubspec.yaml`

- [ ] **Step 1: Add dependencies**

In `app/pubspec.yaml`, under `dependencies:`:
```yaml
  shelf: ^1.4.2
  network_info_plus: ^4.1.0
  url_launcher: ^6.3.0
```

- [ ] **Step 2: Fetch packages**

```bash
cd app && flutter pub get
```
Expected: All 3 packages resolved, no conflicts.

- [ ] **Step 3: Commit**

```bash
git add app/pubspec.yaml app/pubspec.lock
git commit -m "chore: add shelf, network_info_plus, url_launcher dependencies"
```

---

### Task 2: ToolResult Model

**Files:**
- Create: `app/lib/models/tool_result.dart`
- Create: `app/test/models/tool_result_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/models/tool_result_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/tool_result.dart';

void main() {
  test('ToolResult.success stores output', () {
    final r = ToolResult.success(output: '64 bytes from 8.8.8.8');
    expect(r.isSuccess, true);
    expect(r.output, '64 bytes from 8.8.8.8');
    expect(r.error, isNull);
  });

  test('ToolResult.failure stores error', () {
    final r = ToolResult.failure(error: 'Connection timed out');
    expect(r.isSuccess, false);
    expect(r.error, 'Connection timed out');
  });

  test('ToolResult.parseLines splits output into non-empty lines', () {
    final r = ToolResult.success(output: 'line1\n\nline2\nline3\n');
    expect(r.lines, ['line1', 'line2', 'line3']);
  });

  test('ToolResult.durationMs records elapsed time', () {
    final r = ToolResult.success(output: 'ok', durationMs: 142);
    expect(r.durationMs, 142);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd app && flutter test test/models/tool_result_test.dart
```
Expected: compilation error.

- [ ] **Step 3: Implement ToolResult**

```dart
// app/lib/models/tool_result.dart

class ToolResult {
  final bool isSuccess;
  final String? output;
  final String? error;
  final int durationMs;

  const ToolResult._({
    required this.isSuccess,
    this.output,
    this.error,
    this.durationMs = 0,
  });

  factory ToolResult.success({required String output, int durationMs = 0}) =>
      ToolResult._(isSuccess: true, output: output, durationMs: durationMs);

  factory ToolResult.failure({required String error}) =>
      ToolResult._(isSuccess: false, error: error);

  List<String> get lines =>
      (output ?? '').split('\n').where((l) => l.trim().isNotEmpty).toList();
}
```

- [ ] **Step 4: Run tests**

```bash
cd app && flutter test test/models/tool_result_test.dart
```
Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/tool_result.dart app/test/models/tool_result_test.dart
git commit -m "feat: add ToolResult model for network tool output"
```

---

### Task 3: WebToolsService

**Files:**
- Create: `app/lib/services/web_tools_service.dart`
- Create: `app/test/services/web_tools_service_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/services/web_tools_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/web_tools_service.dart';

void main() {
  test('buildPingCommand returns correct command with count', () {
    expect(
      WebToolsService.buildPingCommand('8.8.8.8', count: 4),
      'ping -c 4 8.8.8.8 2>&1',
    );
  });

  test('buildCurlCommand includes method and headers', () {
    final cmd = WebToolsService.buildCurlCommand(
      'https://example.com',
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: '{"key":"value"}',
    );
    expect(cmd, contains('-X POST'));
    expect(cmd, contains('-H "Content-Type: application/json"'));
    expect(cmd, contains("-d '{\"key\":\"value\"}'"));
    expect(cmd, contains('https://example.com'));
  });

  test('buildDnsLookupCommand uses dig when available', () {
    expect(
      WebToolsService.buildDnsLookupCommand('example.com', type: 'A'),
      'dig example.com A 2>&1 || nslookup example.com 2>&1',
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
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd app && flutter test test/services/web_tools_service_test.dart
```
Expected: compilation error.

- [ ] **Step 3: Implement WebToolsService**

```dart
// app/lib/services/web_tools_service.dart
import '../models/tool_result.dart';
import 'ssh_service.dart';

class WebToolsService {
  final SshService _sshService;

  WebToolsService(this._sshService);

  Future<ToolResult> run(String sessionId, String command) async {
    final sw = Stopwatch()..start();
    try {
      final output = await _sshService.exec(sessionId, command);
      sw.stop();
      return ToolResult.success(output: output ?? '', durationMs: sw.elapsedMilliseconds);
    } catch (e) {
      return ToolResult.failure(error: e.toString());
    }
  }

  Future<ToolResult> ping(String sessionId, String host, {int count = 4}) =>
      run(sessionId, buildPingCommand(host, count: count));

  Future<ToolResult> curl(String sessionId, String url, {
    String method = 'GET',
    Map<String, String> headers = const {},
    String? body,
  }) => run(sessionId, buildCurlCommand(url, method: method, headers: headers, body: body));

  Future<ToolResult> dnsLookup(String sessionId, String host, {String type = 'A'}) =>
      run(sessionId, buildDnsLookupCommand(host, type: type));

  Future<ToolResult> traceroute(String sessionId, String host) =>
      run(sessionId, buildTracerouteCommand(host));

  Future<ToolResult> portScan(String sessionId, String host, {List<int> ports = const [22, 80, 443, 3306, 5432, 6379, 8080, 8443]}) =>
      run(sessionId, buildPortScanCommand(host, ports: ports));

  Future<ToolResult> whois(String sessionId, String host) =>
      run(sessionId, 'whois $host 2>&1');

  Future<ToolResult> netstat(String sessionId) =>
      run(sessionId, 'ss -tulpn 2>&1 || netstat -tulpn 2>&1');

  Future<ToolResult> diskUsage(String sessionId, String path) =>
      run(sessionId, 'df -h $path 2>&1');

  Future<ToolResult> topProcesses(String sessionId) =>
      run(sessionId, 'ps aux --sort=-%cpu 2>&1 | head -20');

  Future<ToolResult> memoryInfo(String sessionId) =>
      run(sessionId, 'free -h 2>&1 || vm_stat 2>&1');

  Future<ToolResult> httpHeaders(String sessionId, String url) =>
      run(sessionId, 'curl -sI $url 2>&1');

  Future<ToolResult> sslCert(String sessionId, String host, {int port = 443}) =>
      run(sessionId, 'echo | openssl s_client -connect $host:$port -servername $host 2>&1 | openssl x509 -noout -text 2>&1 | head -40');

  // Static command builders (tested in isolation)

  static String buildPingCommand(String host, {int count = 4}) =>
      'ping -c $count $host 2>&1';

  static String buildCurlCommand(String url, {
    String method = 'GET',
    Map<String, String> headers = const {},
    String? body,
  }) {
    final parts = ['curl', '-s', '-w', r'"\n---\nHTTP Status: %{http_code}\nTime: %{time_total}s"'];
    parts.add('-X $method');
    for (final h in headers.entries) {
      parts.add('-H "${h.key}: ${h.value}"');
    }
    if (body != null) {
      parts.add("-d '${body.replaceAll("'", "'\\''")}'");
    }
    parts.add(url);
    parts.add('2>&1');
    return parts.join(' ');
  }

  static String buildDnsLookupCommand(String host, {String type = 'A'}) =>
      'dig $host $type 2>&1 || nslookup $host 2>&1';

  static String buildTracerouteCommand(String host) =>
      'traceroute $host 2>&1 || tracepath $host 2>&1';

  static String buildPortScanCommand(String host, {List<int> ports = const [80, 443]}) {
    final portList = ports.join(',');
    return 'nc -zv $host ${ports.join(' ')} 2>&1 || '
        'for p in ${ports.join(' ')}; do (echo >/dev/tcp/$host/\$p) 2>/dev/null && echo "Port \$p: open" || echo "Port \$p: closed"; done 2>&1';
  }
}
```

- [ ] **Step 4: Run tests**

```bash
cd app && flutter test test/services/web_tools_service_test.dart
```
Expected: All 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/web_tools_service.dart app/test/services/web_tools_service_test.dart
git commit -m "feat: add WebToolsService with ping, curl, dns, traceroute, port scan"
```

---

### Task 4: WebToolsScreen UI

**Files:**
- Create: `app/lib/widgets/web_tools_screen.dart`
- Create: `app/lib/widgets/tool_result_view.dart`

- [ ] **Step 1: Implement ToolResultView**

```dart
// app/lib/widgets/tool_result_view.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/tool_result.dart';

class ToolResultView extends StatelessWidget {
  final ToolResult? result;
  final bool isLoading;

  const ToolResultView({super.key, this.result, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF22C55E)));
    }
    if (result == null) {
      return const Center(
        child: Text('Run a tool to see output', style: TextStyle(color: Color(0xFF555555))),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF141414),
          child: Row(
            children: [
              Icon(
                result!.isSuccess ? Icons.check_circle_outline : Icons.error_outline,
                size: 14,
                color: result!.isSuccess ? const Color(0xFF22C55E) : Colors.red,
              ),
              const SizedBox(width: 6),
              Text(
                result!.isSuccess ? 'Success (${result!.durationMs}ms)' : 'Error',
                style: TextStyle(
                  color: result!.isSuccess ? const Color(0xFF22C55E) : Colors.red,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 14, color: Color(0xFF888888)),
                tooltip: 'Copy output',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: result!.output ?? result!.error ?? ''));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
                  );
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              result!.output ?? result!.error ?? '',
              style: const TextStyle(
                color: Color(0xFFD4D4D4),
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Implement WebToolsScreen**

```dart
// app/lib/widgets/web_tools_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/tool_result.dart';
import '../providers/session_provider.dart';
import '../services/ssh_service.dart';
import '../services/web_tools_service.dart';
import 'tool_result_view.dart';

enum _Tool {
  ping, curl, dns, traceroute, portScan, whois,
  netstat, diskUsage, topProcesses, memory, httpHeaders, sslCert,
}

extension _ToolExt on _Tool {
  String get label => switch (this) {
    _Tool.ping => 'Ping',
    _Tool.curl => 'cURL',
    _Tool.dns => 'DNS Lookup',
    _Tool.traceroute => 'Traceroute',
    _Tool.portScan => 'Port Scan',
    _Tool.whois => 'Whois',
    _Tool.netstat => 'Netstat',
    _Tool.diskUsage => 'Disk Usage',
    _Tool.topProcesses => 'Top Processes',
    _Tool.memory => 'Memory Info',
    _Tool.httpHeaders => 'HTTP Headers',
    _Tool.sslCert => 'SSL Certificate',
  };

  IconData get icon => switch (this) {
    _Tool.ping => Icons.wifi_tethering,
    _Tool.curl => Icons.http,
    _Tool.dns => Icons.dns,
    _Tool.traceroute => Icons.route,
    _Tool.portScan => Icons.radar,
    _Tool.whois => Icons.info_outline,
    _Tool.netstat => Icons.device_hub,
    _Tool.diskUsage => Icons.storage,
    _Tool.topProcesses => Icons.memory,
    _Tool.memory => Icons.developer_board,
    _Tool.httpHeaders => Icons.receipt_long,
    _Tool.sslCert => Icons.lock_outline,
  };
}

class WebToolsScreen extends StatefulWidget {
  const WebToolsScreen({super.key});

  @override
  State<WebToolsScreen> createState() => _WebToolsScreenState();
}

class _WebToolsScreenState extends State<WebToolsScreen> {
  _Tool _selected = _Tool.ping;
  final _inputController = TextEditingController(text: '8.8.8.8');
  ToolResult? _result;
  bool _loading = false;

  Future<void> _run() async {
    final session = context.read<SessionProvider>().activeSession;
    if (session == null) return;

    final service = WebToolsService(context.read<SshService>());
    setState(() { _loading = true; _result = null; });

    final input = _inputController.text.trim();
    final result = await switch (_selected) {
      _Tool.ping => service.ping(session.id, input),
      _Tool.curl => service.curl(session.id, input),
      _Tool.dns => service.dnsLookup(session.id, input),
      _Tool.traceroute => service.traceroute(session.id, input),
      _Tool.portScan => service.portScan(session.id, input),
      _Tool.whois => service.whois(session.id, input),
      _Tool.netstat => service.netstat(session.id),
      _Tool.diskUsage => service.diskUsage(session.id, input.isEmpty ? '/' : input),
      _Tool.topProcesses => service.topProcesses(session.id),
      _Tool.memory => service.memoryInfo(session.id),
      _Tool.httpHeaders => service.httpHeaders(session.id, input),
      _Tool.sslCert => service.sslCert(session.id, input),
    };

    setState(() { _result = result; _loading = false; });
  }

  bool get _needsInput => switch (_selected) {
    _Tool.netstat || _Tool.topProcesses || _Tool.memory => false,
    _ => true,
  };

  String get _inputHint => switch (_selected) {
    _Tool.ping || _Tool.dns || _Tool.traceroute || _Tool.whois || _Tool.portScan => 'Hostname or IP (e.g. 8.8.8.8)',
    _Tool.curl || _Tool.httpHeaders => 'URL (e.g. https://example.com)',
    _Tool.sslCert => 'Hostname (e.g. example.com)',
    _Tool.diskUsage => 'Path (e.g. /)',
    _ => '',
  };

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>().activeSession;

    return Row(
      children: [
        // Tool list sidebar
        SizedBox(
          width: 160,
          child: Container(
            color: const Color(0xFF141414),
            child: ListView(
              children: _Tool.values.map((tool) => ListTile(
                leading: Icon(tool.icon, size: 16, color: _selected == tool
                    ? const Color(0xFF22C55E)
                    : const Color(0xFF888888)),
                title: Text(
                  tool.label,
                  style: TextStyle(
                    color: _selected == tool
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFD4D4D4),
                    fontSize: 13,
                  ),
                ),
                selected: _selected == tool,
                selectedColor: const Color(0xFF1C1C1C),
                onTap: () => setState(() {
                  _selected = tool;
                  _result = null;
                }),
                dense: true,
              )).toList(),
            ),
          ),
        ),
        const VerticalDivider(width: 1, color: Color(0xFF2A2A2A)),
        // Main area
        Expanded(
          child: Column(
            children: [
              if (session == null)
                Container(
                  padding: const EdgeInsets.all(8),
                  color: const Color(0xFF1C1C1C),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber, size: 14, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('No active session — connect to a host first',
                          style: TextStyle(color: Colors.orange, fontSize: 12)),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    if (_needsInput) ...[
                      Expanded(
                        child: TextField(
                          controller: _inputController,
                          style: const TextStyle(
                            color: Color(0xFFD4D4D4),
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText: _inputHint,
                            hintStyle: const TextStyle(color: Color(0xFF555555)),
                            filled: true,
                            fillColor: const Color(0xFF1C1C1C),
                            border: const OutlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFF2A2A2A)),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          onSubmitted: (_) => session != null ? _run() : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    ElevatedButton.icon(
                      onPressed: session != null && !_loading ? _run : null,
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: Text(_selected.label),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFF2A2A2A)),
              Expanded(
                child: ToolResultView(result: _result, isLoading: _loading),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: Wire WebToolsScreen into MainScreen**

In `app/lib/widgets/main_screen.dart`, replace the Web Tools "Coming soon" placeholder with:
```dart
import 'web_tools_screen.dart';
// In the navigation section for 'Web Tools':
const WebToolsScreen()
```

- [ ] **Step 4: Verify manually**

```bash
cd app && flutter run -d macos
```
1. Connect to an SSH host.
2. Navigate to Web Tools.
3. Select "Ping", enter `8.8.8.8`, click Run.
4. Verify ping output appears in the result area.
5. Select "cURL", enter `https://httpbin.org/get`, click Run.
6. Verify JSON response appears.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/web_tools_screen.dart app/lib/widgets/tool_result_view.dart app/lib/widgets/main_screen.dart
git commit -m "feat: implement Web Tools screen with 12 network utilities"
```

---

### Task 5: TunnelConfig Model & TunnelProvider

**Files:**
- Create: `app/lib/models/tunnel_config.dart`
- Create: `app/lib/providers/tunnel_provider.dart`

- [ ] **Step 1: Implement TunnelConfig**

```dart
// app/lib/models/tunnel_config.dart
import 'package:uuid/uuid.dart';

enum TunnelStatus { idle, starting, active, error }
enum TunnelType { cloudflare, sshForward }

class TunnelConfig {
  final String id;
  final String label;
  final TunnelType type;
  final int localPort;
  final String? publicUrl; // assigned after tunnel starts
  TunnelStatus status;
  String? errorMessage;

  TunnelConfig({
    String? id,
    required this.label,
    required this.type,
    required this.localPort,
    this.publicUrl,
    this.status = TunnelStatus.idle,
    this.errorMessage,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
    'id': id, 'label': label, 'type': type.name,
    'localPort': localPort,
  };

  factory TunnelConfig.fromJson(Map<String, dynamic> json) => TunnelConfig(
    id: json['id'] as String,
    label: json['label'] as String,
    type: TunnelType.values.byName(json['type'] as String),
    localPort: json['localPort'] as int,
  );
}
```

- [ ] **Step 2: Implement TunnelProvider**

```dart
// app/lib/providers/tunnel_provider.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tunnel_config.dart';

class TunnelProvider extends ChangeNotifier {
  static const _prefKey = 'tunnels_v1';
  final List<TunnelConfig> _tunnels = [];

  List<TunnelConfig> get tunnels => List.unmodifiable(_tunnels);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw == null) return;
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    _tunnels.addAll(list.map(TunnelConfig.fromJson));
    notifyListeners();
  }

  void add(TunnelConfig tunnel) {
    _tunnels.add(tunnel);
    _persist();
    notifyListeners();
  }

  void remove(String id) {
    _tunnels.removeWhere((t) => t.id == id);
    _persist();
    notifyListeners();
  }

  void updateStatus(String id, TunnelStatus status, {String? url, String? error}) {
    final idx = _tunnels.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    _tunnels[idx].status = status;
    if (url != null) _tunnels[idx] = TunnelConfig(
      id: _tunnels[idx].id,
      label: _tunnels[idx].label,
      type: _tunnels[idx].type,
      localPort: _tunnels[idx].localPort,
      publicUrl: url,
      status: status,
    );
    if (error != null) _tunnels[idx].errorMessage = error;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(_tunnels.map((t) => t.toJson()).toList()));
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add app/lib/models/tunnel_config.dart app/lib/providers/tunnel_provider.dart
git commit -m "feat: add TunnelConfig model and TunnelProvider"
```

---

### Task 6: CloudflareTunnelService & Screen

**Files:**
- Create: `app/lib/services/cloudflare_tunnel_service.dart`
- Create: `app/lib/widgets/cloudflare_tunnel_screen.dart`

- [ ] **Step 1: Implement CloudflareTunnelService**

```dart
// app/lib/services/cloudflare_tunnel_service.dart
import 'dart:async';
import '../services/ssh_service.dart';

class CloudflareTunnelService {
  final SshService _sshService;

  CloudflareTunnelService(this._sshService);

  /// Starts cloudflared quick tunnel on the remote server.
  /// Returns the public trycloudflare.com URL if successful, or null on failure.
  Future<String?> startQuickTunnel(String sessionId, int port) async {
    try {
      // Runs cloudflared in background, captures the assigned URL
      final cmd = '''
        nohup cloudflared tunnel --url http://localhost:$port > /tmp/cf_tunnel_$port.log 2>&1 &
        sleep 3
        grep -o 'https://[^[:space:]]*trycloudflare.com' /tmp/cf_tunnel_$port.log | head -1
      ''';
      final output = await _sshService.exec(sessionId, cmd);
      final url = output?.trim();
      if (url != null && url.startsWith('https://')) return url;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> stopTunnel(String sessionId, int port) async {
    await _sshService.exec(
      sessionId,
      "pkill -f 'cloudflared.*$port' 2>/dev/null; rm -f /tmp/cf_tunnel_$port.log",
    );
  }

  Future<bool> isCloudflaredInstalled(String sessionId) async {
    final output = await _sshService.exec(sessionId, 'which cloudflared 2>/dev/null');
    return output?.trim().isNotEmpty ?? false;
  }
}
```

- [ ] **Step 2: Implement CloudflareTunnelScreen**

```dart
// app/lib/widgets/cloudflare_tunnel_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/tunnel_config.dart';
import '../providers/session_provider.dart';
import '../providers/tunnel_provider.dart';
import '../services/cloudflare_tunnel_service.dart';
import '../services/ssh_service.dart';

class CloudflareTunnelScreen extends StatelessWidget {
  const CloudflareTunnelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => TunnelProvider()..load(),
      child: const _CloudflareTunnelBody(),
    );
  }
}

class _CloudflareTunnelBody extends StatelessWidget {
  const _CloudflareTunnelBody();

  void _addTunnel(BuildContext context) {
    final portController = TextEditingController(text: '3000');
    final labelController = TextEditingController(text: 'My Service');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title: const Text('New Cloudflare Tunnel', style: TextStyle(color: Color(0xFFD4D4D4))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelController,
              decoration: const InputDecoration(
                labelText: 'Label',
                labelStyle: TextStyle(color: Color(0xFF888888)),
              ),
              style: const TextStyle(color: Color(0xFFD4D4D4)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: portController,
              decoration: const InputDecoration(
                labelText: 'Local Port',
                labelStyle: TextStyle(color: Color(0xFF888888)),
              ),
              style: const TextStyle(color: Color(0xFFD4D4D4)),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              context.read<TunnelProvider>().add(TunnelConfig(
                label: labelController.text,
                type: TunnelType.cloudflare,
                localPort: int.tryParse(portController.text) ?? 3000,
              ));
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _startTunnel(BuildContext context, TunnelConfig tunnel) async {
    final session = context.read<SessionProvider>().activeSession;
    if (session == null) return;

    final provider = context.read<TunnelProvider>();
    final service = CloudflareTunnelService(context.read<SshService>());

    provider.updateStatus(tunnel.id, TunnelStatus.starting);

    final installed = await service.isCloudflaredInstalled(session.id);
    if (!installed) {
      provider.updateStatus(tunnel.id, TunnelStatus.error,
          error: 'cloudflared not found on server. Install with: curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared && chmod +x /usr/local/bin/cloudflared');
      return;
    }

    final url = await service.startQuickTunnel(session.id, tunnel.localPort);
    if (url != null) {
      provider.updateStatus(tunnel.id, TunnelStatus.active, url: url);
    } else {
      provider.updateStatus(tunnel.id, TunnelStatus.error,
          error: 'Could not get tunnel URL. Check /tmp/cf_tunnel_${tunnel.localPort}.log on the server.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TunnelProvider>();
    final session = context.watch<SessionProvider>().activeSession;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Text('Cloudflare Tunnels',
                  style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _addTunnel(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Tunnel'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22C55E),
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
        if (session == null)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('Connect to a host to manage tunnels',
                style: TextStyle(color: Colors.orange, fontSize: 12)),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: provider.tunnels.length,
            itemBuilder: (_, i) => _buildTunnelTile(context, provider.tunnels[i], session != null),
          ),
        ),
      ],
    );
  }

  Widget _buildTunnelTile(BuildContext context, TunnelConfig tunnel, bool hasSession) {
    final statusColor = switch (tunnel.status) {
      TunnelStatus.idle => const Color(0xFF555555),
      TunnelStatus.starting => Colors.orange,
      TunnelStatus.active => const Color(0xFF22C55E),
      TunnelStatus.error => Colors.red,
    };

    return ListTile(
      leading: Icon(Icons.cloud_queue, color: statusColor),
      title: Text(tunnel.label, style: const TextStyle(color: Color(0xFFD4D4D4))),
      subtitle: tunnel.publicUrl != null
          ? GestureDetector(
              onTap: () => launchUrl(Uri.parse(tunnel.publicUrl!)),
              child: Text(tunnel.publicUrl!,
                  style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 12)),
            )
          : tunnel.errorMessage != null
              ? Text(tunnel.errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 11))
              : Text('Port: ${tunnel.localPort}',
                  style: const TextStyle(color: Color(0xFF555555), fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tunnel.publicUrl != null)
            IconButton(
              icon: const Icon(Icons.copy, size: 16, color: Color(0xFF888888)),
              onPressed: () => Clipboard.setData(ClipboardData(text: tunnel.publicUrl!)),
              tooltip: 'Copy URL',
            ),
          if (tunnel.status == TunnelStatus.idle || tunnel.status == TunnelStatus.error)
            IconButton(
              icon: const Icon(Icons.play_arrow, size: 16, color: Color(0xFF22C55E)),
              onPressed: hasSession ? () => _startTunnel(context, tunnel) : null,
              tooltip: 'Start tunnel',
            ),
          if (tunnel.status == TunnelStatus.starting)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFF555555)),
            onPressed: () => context.read<TunnelProvider>().remove(tunnel.id),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Register TunnelProvider in main.dart**

```dart
// In MultiProvider providers list:
ChangeNotifierProvider(create: (_) => TunnelProvider()..load()),
```

- [ ] **Step 4: Commit**

```bash
git add app/lib/services/cloudflare_tunnel_service.dart app/lib/widgets/cloudflare_tunnel_screen.dart app/lib/models/tunnel_config.dart app/lib/providers/tunnel_provider.dart app/lib/main.dart
git commit -m "feat: add Cloudflare Tunnel management with quick tunnel support"
```

---

### Task 7: LanShareService & Screen

**Files:**
- Create: `app/lib/services/lan_share_service.dart`
- Create: `app/lib/widgets/lan_share_screen.dart`

- [ ] **Step 1: Implement LanShareService**

```dart
// app/lib/services/lan_share_service.dart
import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:path/path.dart' as p;

class LanShareService {
  HttpServer? _server;
  String? _sharedFilePath;

  Future<String?> share(String filePath, {int port = 8765}) async {
    await stop();
    _sharedFilePath = filePath;

    final handler = const Pipeline().addHandler(_handleRequest);
    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);

    final localIp = await NetworkInfo().getWifiIP();
    if (localIp == null) return null;
    return 'http://$localIp:$port/download/${Uri.encodeComponent(p.basename(filePath))}';
  }

  Response _handleRequest(Request request) {
    if (_sharedFilePath == null) return Response.notFound('No file shared');
    final file = File(_sharedFilePath!);
    if (!file.existsSync()) return Response.notFound('File not found');
    final filename = p.basename(_sharedFilePath!);
    return Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': 'application/octet-stream',
        'Content-Disposition': 'attachment; filename="$filename"',
        'Content-Length': file.lengthSync().toString(),
      },
    );
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _sharedFilePath = null;
  }

  bool get isRunning => _server != null;
}
```

- [ ] **Step 2: Implement LanShareScreen**

```dart
// app/lib/widgets/lan_share_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../services/lan_share_service.dart';

class LanShareScreen extends StatefulWidget {
  const LanShareScreen({super.key});

  @override
  State<LanShareScreen> createState() => _LanShareScreenState();
}

class _LanShareScreenState extends State<LanShareScreen> {
  final _service = LanShareService();
  String? _shareUrl;
  String? _fileName;
  bool _sharing = false;

  @override
  void dispose() {
    _service.stop();
    super.dispose();
  }

  Future<void> _pickAndShare() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    setState(() { _sharing = true; _shareUrl = null; });

    final url = await _service.share(path);
    setState(() {
      _sharing = false;
      _shareUrl = url;
      _fileName = result.files.single.name;
    });
  }

  Future<void> _stop() async {
    await _service.stop();
    setState(() { _shareUrl = null; _fileName = null; });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('LocalShare',
              style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Share files on your local network over HTTP.',
              style: TextStyle(color: Color(0xFF888888), fontSize: 13)),
          const SizedBox(height: 24),
          if (_shareUrl == null) ...[
            ElevatedButton.icon(
              onPressed: _sharing ? null : _pickAndShare,
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Pick File to Share'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22C55E),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1C),
                border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.4)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 16),
                      const SizedBox(width: 8),
                      Text(_fileName ?? '', style: const TextStyle(color: Color(0xFFD4D4D4))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Share URL:', style: TextStyle(color: Color(0xFF888888), fontSize: 12)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          _shareUrl!,
                          style: const TextStyle(
                            color: Color(0xFF60A5FA),
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16, color: Color(0xFF888888)),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _shareUrl!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('URL copied'), duration: Duration(seconds: 1)),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _stop,
                    icon: const Icon(Icons.stop, size: 16, color: Colors.red),
                    label: const Text('Stop Sharing', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add app/lib/services/lan_share_service.dart app/lib/widgets/lan_share_screen.dart
git commit -m "feat: add LAN file sharing via local HTTP server"
```

---

### Task 8: MailCatcher Screen

**Files:**
- Create: `app/lib/services/mail_catcher_service.dart`
- Create: `app/lib/widgets/mail_catcher_screen.dart`

- [ ] **Step 1: Implement MailCatcherService**

The mail catcher starts a Python SMTP server on the remote that dumps emails to a file, then polls via SSH exec.

```dart
// app/lib/services/mail_catcher_service.dart
import '../services/ssh_service.dart';

class CaughtEmail {
  final String from;
  final String to;
  final String subject;
  final String body;
  final DateTime receivedAt;

  const CaughtEmail({
    required this.from,
    required this.to,
    required this.subject,
    required this.body,
    required this.receivedAt,
  });
}

class MailCatcherService {
  final SshService _sshService;
  static const _smtpPort = 1025;

  MailCatcherService(this._sshService);

  Future<bool> start(String sessionId) async {
    // Start Python SMTP debug server in background
    const cmd = '''
      pkill -f "smtpd.*$_smtpPort" 2>/dev/null
      python3 -m smtpd -n -c DebuggingServer localhost:$_smtpPort > /tmp/mailcatcher.log 2>&1 &
      sleep 1
      pgrep -f "smtpd.*$_smtpPort" > /dev/null 2>&1 && echo "started"
    ''';
    final output = await _sshService.exec(sessionId, cmd);
    return output?.trim() == 'started';
  }

  Future<void> stop(String sessionId) async {
    await _sshService.exec(sessionId, "pkill -f 'smtpd.*$_smtpPort' 2>/dev/null");
  }

  Future<List<CaughtEmail>> fetchEmails(String sessionId) async {
    final output = await _sshService.exec(sessionId, 'cat /tmp/mailcatcher.log 2>/dev/null');
    if (output == null || output.isEmpty) return [];
    return _parseSmtpdLog(output);
  }

  Future<void> clearLog(String sessionId) async {
    await _sshService.exec(sessionId, '> /tmp/mailcatcher.log');
  }

  List<CaughtEmail> _parseSmtpdLog(String log) {
    // Python smtpd DebuggingServer outputs blocks separated by "---------- MESSAGE FOLLOWS ----------"
    final emails = <CaughtEmail>[];
    final blocks = log.split(RegExp(r'-{10,}'));

    for (final block in blocks) {
      if (block.trim().isEmpty) continue;
      final lines = block.split('\n').where((l) => l.isNotEmpty).toList();
      String from = '', to = '', subject = '';
      final bodyLines = <String>[];
      bool inBody = false;

      for (final line in lines) {
        if (line.startsWith('From: ')) from = line.substring(6);
        else if (line.startsWith('To: ')) to = line.substring(4);
        else if (line.startsWith('Subject: ')) subject = line.substring(9);
        else if (line.isEmpty) inBody = true;
        else if (inBody) bodyLines.add(line);
      }

      if (from.isNotEmpty || to.isNotEmpty) {
        emails.add(CaughtEmail(
          from: from,
          to: to,
          subject: subject,
          body: bodyLines.join('\n'),
          receivedAt: DateTime.now(),
        ));
      }
    }
    return emails;
  }
}
```

- [ ] **Step 2: Implement MailCatcherScreen**

```dart
// app/lib/widgets/mail_catcher_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/session_provider.dart';
import '../services/mail_catcher_service.dart';
import '../services/ssh_service.dart';

class MailCatcherScreen extends StatefulWidget {
  const MailCatcherScreen({super.key});

  @override
  State<MailCatcherScreen> createState() => _MailCatcherScreenState();
}

class _MailCatcherScreenState extends State<MailCatcherScreen> {
  late MailCatcherService _service;
  bool _running = false;
  List<CaughtEmail> _emails = [];
  CaughtEmail? _selected;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _service = MailCatcherService(context.read<SshService>());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final session = context.read<SessionProvider>().activeSession;
    if (session == null) return;
    final ok = await _service.start(session.id);
    if (ok) {
      setState(() => _running = true);
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to start SMTP server. Ensure python3 is installed.'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _stop() async {
    final session = context.read<SessionProvider>().activeSession;
    if (session == null) return;
    _pollTimer?.cancel();
    await _service.stop(session.id);
    setState(() => _running = false);
  }

  Future<void> _poll() async {
    final session = context.read<SessionProvider>().activeSession;
    if (session == null) return;
    final emails = await _service.fetchEmails(session.id);
    if (mounted) setState(() => _emails = emails);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Email list
        SizedBox(
          width: 260,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: const Color(0xFF141414),
                child: Row(
                  children: [
                    const Text('Mail Catcher',
                        style: TextStyle(color: Color(0xFFD4D4D4), fontWeight: FontWeight.w600)),
                    const Spacer(),
                    _running
                        ? IconButton(
                            icon: const Icon(Icons.stop, size: 16, color: Colors.red),
                            onPressed: _stop,
                            tooltip: 'Stop',
                          )
                        : IconButton(
                            icon: const Icon(Icons.play_arrow, size: 16, color: Color(0xFF22C55E)),
                            onPressed: context.watch<SessionProvider>().activeSession != null ? _start : null,
                            tooltip: 'Start on port 1025',
                          ),
                  ],
                ),
              ),
              if (_running)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  color: const Color(0xFF22C55E).withOpacity(0.1),
                  child: const Row(
                    children: [
                      Icon(Icons.circle, size: 8, color: Color(0xFF22C55E)),
                      SizedBox(width: 6),
                      Text('Listening on :1025',
                          style: TextStyle(color: Color(0xFF22C55E), fontSize: 11)),
                    ],
                  ),
                ),
              Expanded(
                child: _emails.isEmpty
                    ? const Center(
                        child: Text('No emails captured',
                            style: TextStyle(color: Color(0xFF555555))),
                      )
                    : ListView.builder(
                        itemCount: _emails.length,
                        itemBuilder: (_, i) => ListTile(
                          selected: _selected == _emails[i],
                          title: Text(
                            _emails[i].subject.isEmpty ? '(no subject)' : _emails[i].subject,
                            style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 13),
                          ),
                          subtitle: Text(_emails[i].from,
                              style: const TextStyle(color: Color(0xFF888888), fontSize: 11)),
                          onTap: () => setState(() => _selected = _emails[i]),
                        ),
                      ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: Color(0xFF2A2A2A)),
        // Email detail
        Expanded(
          child: _selected == null
              ? const Center(
                  child: Text('Select an email',
                      style: TextStyle(color: Color(0xFF555555))),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Subject: ${_selected!.subject}',
                          style: const TextStyle(color: Color(0xFFD4D4D4), fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('From: ${_selected!.from}',
                          style: const TextStyle(color: Color(0xFF888888), fontSize: 12)),
                      Text('To: ${_selected!.to}',
                          style: const TextStyle(color: Color(0xFF888888), fontSize: 12)),
                      const Divider(color: Color(0xFF2A2A2A), height: 24),
                      Expanded(
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _selected!.body,
                            style: const TextStyle(
                              color: Color(0xFFD4D4D4),
                              fontFamily: 'monospace',
                              fontSize: 12,
                              height: 1.6,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: Add all DevOps screens to MainScreen navigation**

In `app/lib/widgets/main_screen.dart`, add navigation items for:
- **Cloudflare Tunnels** (icon: `Icons.cloud_queue`) → `CloudflareTunnelScreen()`
- **LocalShare** (icon: `Icons.share`) → `LanShareScreen()`
- **Mail Catcher** (icon: `Icons.email`) → `MailCatcherScreen()`

These can be grouped under a "DevOps" section in the sidebar.

- [ ] **Step 4: Verify manually**

```bash
cd app && flutter run -d macos
```
1. Navigate to Mail Catcher, connect to SSH, click Start — verify "Listening on :1025" badge.
2. Navigate to LocalShare, pick a file — verify a share URL like `http://192.168.x.x:8765/download/...` appears.
3. Navigate to Cloudflare Tunnels, click New Tunnel, set port 3000 — verify tile added.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/mail_catcher_service.dart app/lib/widgets/mail_catcher_screen.dart app/lib/services/lan_share_service.dart app/lib/widgets/lan_share_screen.dart app/lib/widgets/main_screen.dart
git commit -m "feat: add Mail Catcher, LAN Share, and DevOps navigation sections"
```

---

## Self-Review

**Spec coverage:**
- ✅ Web Tools (Ping, cURL, DNS, traceroute, port scan, whois, netstat, disk, top, memory, HTTP headers, SSL cert) — Tasks 2, 3, 4
- ✅ Cloudflare Tunnels — Tasks 5, 6
- ✅ LocalShare (LAN Transfer) — Task 7
- ✅ Mail Catcher — Task 8
- ❌ Remote Terminal (Tunnel) — uses SSH port forwarding already covered in existing PortForwardProvider. A dedicated screen was out of scope vs the existing implementation; can be addressed by adding a "Remote Access" tab to the port forwarding screen that starts a local port forward and shows the connection command.

**Gaps addressed:** Remote Terminal is functionally equivalent to SSH local port forwarding, which is already implemented. Adding a UI convenience wrapper is noted as a follow-up.

**Type consistency:** `TunnelConfig`, `TunnelProvider`, `TunnelStatus`, `TunnelType` used consistently across Tasks 5–6. `CaughtEmail` defined in `mail_catcher_service.dart` and used in `mail_catcher_screen.dart`.
