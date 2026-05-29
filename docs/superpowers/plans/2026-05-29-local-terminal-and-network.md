# Local Terminal & Network Monitor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Built-in Local Terminal (native shell access inside the app), Tmux Integration, and a Network Stats Monitor widget.

**Architecture:** Local terminal uses `dart:io Process.start()` to spawn the user's shell (`$SHELL` or `/bin/zsh`), piping PTY I/O through an `xterm` Terminal widget — mirroring how `SshService.openShell()` works for remote sessions. Tmux is exposed as a toggle that wraps the remote shell command: instead of opening a bare shell the SSH session runs `tmux new -As yourssh`. Network stats are polled from `/proc/net/dev` (Linux) or `netstat`/`nettop` (macOS) via an SSH exec call on the active connection, displayed as a compact overlay.

**Tech Stack:** Flutter, `dart:io` (Process), `xterm`, `provider`, `dartssh2`

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `app/lib/services/local_shell_service.dart` | Create | Spawn and manage local PTY process |
| `app/lib/models/local_session.dart` | Create | Wraps local process + xterm Terminal |
| `app/lib/providers/local_session_provider.dart` | Create | Local session state |
| `app/lib/widgets/local_terminal_screen.dart` | Create | UI for local terminal |
| `app/lib/services/network_stats_service.dart` | Create | Poll SSH exec for network I/O stats |
| `app/lib/models/network_stats.dart` | Create | Parsed Rx/Tx data |
| `app/lib/widgets/network_stats_overlay.dart` | Create | HUD overlay showing stats |
| `app/lib/providers/settings_provider.dart` | Modify | Add `tmuxEnabled`, `networkStatsEnabled` |
| `app/lib/widgets/main_screen.dart` | Modify | Add Local Terminal nav item, network stats overlay |
| `app/test/models/network_stats_test.dart` | Create | Unit tests for stats parsing |
| `app/test/services/network_stats_service_test.dart` | Create | Unit tests for service |

---

### Task 1: NetworkStats Model & Parser

**Files:**
- Create: `app/lib/models/network_stats.dart`
- Create: `app/test/models/network_stats_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/models/network_stats_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/network_stats.dart';

void main() {
  group('NetworkStats.fromProcNetDev', () {
    const linuxOutput = '''
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo: 12345678       0    0    0    0     0          0         0 12345678       0    0    0    0     0       0          0
  eth0: 987654321   12345    0    0    0     0          0      1234 112233445   54321    0    0    0     0       0          0
''';

    test('parses eth0 rx and tx bytes', () {
      final stats = NetworkStats.fromProcNetDev(linuxOutput, interface: 'eth0');
      expect(stats.rxBytes, 987654321);
      expect(stats.txBytes, 112233445);
      expect(stats.interface, 'eth0');
    });

    test('returns zero stats when interface not found', () {
      final stats = NetworkStats.fromProcNetDev(linuxOutput, interface: 'wlan0');
      expect(stats.rxBytes, 0);
      expect(stats.txBytes, 0);
    });
  });

  group('NetworkStats.formatBytes', () {
    test('formats bytes correctly', () {
      expect(NetworkStats.formatBytes(512), '512 B/s');
      expect(NetworkStats.formatBytes(1536), '1.5 KB/s');
      expect(NetworkStats.formatBytes(1572864), '1.5 MB/s');
    });
  });

  group('NetworkStats.delta', () {
    test('computes per-second rates from two snapshots', () {
      final s1 = NetworkStats(interface: 'eth0', rxBytes: 1000, txBytes: 500, timestamp: DateTime(2024, 1, 1, 0, 0, 0));
      final s2 = NetworkStats(interface: 'eth0', rxBytes: 3000, txBytes: 1500, timestamp: DateTime(2024, 1, 1, 0, 0, 2));
      final delta = s2.delta(s1);
      expect(delta.rxBytesPerSec, 1000); // (3000-1000)/2s
      expect(delta.txBytesPerSec, 500);  // (1500-500)/2s
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd app && flutter test test/models/network_stats_test.dart
```
Expected: compilation error.

- [ ] **Step 3: Implement NetworkStats**

```dart
// app/lib/models/network_stats.dart

class NetworkStats {
  final String interface;
  final int rxBytes;
  final int txBytes;
  final DateTime timestamp;

  const NetworkStats({
    required this.interface,
    required this.rxBytes,
    required this.txBytes,
    required this.timestamp,
  });

  factory NetworkStats.fromProcNetDev(String output, {required String interface}) {
    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('$interface:')) continue;
      final parts = trimmed.replaceFirst('$interface:', '').trim().split(RegExp(r'\s+'));
      if (parts.length < 9) continue;
      return NetworkStats(
        interface: interface,
        rxBytes: int.tryParse(parts[0]) ?? 0,
        txBytes: int.tryParse(parts[8]) ?? 0,
        timestamp: DateTime.now(),
      );
    }
    return NetworkStats(interface: interface, rxBytes: 0, txBytes: 0, timestamp: DateTime.now());
  }

  NetworkStatsDelta delta(NetworkStats previous) {
    final seconds = timestamp.difference(previous.timestamp).inMilliseconds / 1000.0;
    if (seconds <= 0) return NetworkStatsDelta(rxBytesPerSec: 0, txBytesPerSec: 0);
    return NetworkStatsDelta(
      rxBytesPerSec: ((rxBytes - previous.rxBytes) / seconds).round().clamp(0, double.maxFinite.toInt()),
      txBytesPerSec: ((txBytes - previous.txBytes) / seconds).round().clamp(0, double.maxFinite.toInt()),
    );
  }

  static String formatBytes(int bytesPerSec) {
    if (bytesPerSec < 1024) return '$bytesPerSec B/s';
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}

class NetworkStatsDelta {
  final int rxBytesPerSec;
  final int txBytesPerSec;
  const NetworkStatsDelta({required this.rxBytesPerSec, required this.txBytesPerSec});
}
```

- [ ] **Step 4: Run tests**

```bash
cd app && flutter test test/models/network_stats_test.dart
```
Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/network_stats.dart app/test/models/network_stats_test.dart
git commit -m "feat: add NetworkStats model with /proc/net/dev parsing"
```

---

### Task 2: NetworkStatsService

**Files:**
- Create: `app/lib/services/network_stats_service.dart`
- Create: `app/test/services/network_stats_service_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/services/network_stats_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/network_stats_service.dart';

void main() {
  test('detectPrimaryInterface returns non-empty string from mock output', () {
    const output = '''
Inter-|   Receive
 face |bytes
    lo:    100
  eth0:  99999
''';
    final iface = NetworkStatsService.detectPrimaryInterface(output);
    expect(iface, 'eth0');
  });

  test('detectPrimaryInterface ignores loopback', () {
    const output = '    lo: 100\n';
    final iface = NetworkStatsService.detectPrimaryInterface(output);
    expect(iface, isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd app && flutter test test/services/network_stats_service_test.dart
```
Expected: compilation error.

- [ ] **Step 3: Implement NetworkStatsService**

```dart
// app/lib/services/network_stats_service.dart
import 'dart:async';
import '../models/network_stats.dart';
import 'ssh_service.dart';

class NetworkStatsService {
  Timer? _timer;
  NetworkStats? _previous;
  final void Function(NetworkStatsDelta delta) onUpdate;
  final String sessionId;
  final SshService sshService;

  NetworkStatsService({
    required this.sessionId,
    required this.sshService,
    required this.onUpdate,
  });

  void start({Duration interval = const Duration(seconds: 2)}) {
    _timer = Timer.periodic(interval, (_) => _poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    try {
      final output = await sshService.exec(sessionId, 'cat /proc/net/dev 2>/dev/null || netstat -ib 2>/dev/null');
      if (output == null || output.isEmpty) return;
      final iface = detectPrimaryInterface(output);
      if (iface == null) return;
      final current = NetworkStats.fromProcNetDev(output, interface: iface);
      if (_previous != null) {
        onUpdate(current.delta(_previous!));
      }
      _previous = current;
    } catch (_) {
      // SSH exec may fail if session disconnects — silently ignore
    }
  }

  static String? detectPrimaryInterface(String procNetDevOutput) {
    for (final line in procNetDevOutput.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('Inter') || trimmed.startsWith('face')) continue;
      final colonIdx = trimmed.indexOf(':');
      if (colonIdx < 0) continue;
      final name = trimmed.substring(0, colonIdx).trim();
      if (name == 'lo') continue;
      return name;
    }
    return null;
  }
}
```

- [ ] **Step 4: Run tests**

```bash
cd app && flutter test test/services/network_stats_service_test.dart
```
Expected: Both tests pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/network_stats_service.dart app/test/services/network_stats_service_test.dart
git commit -m "feat: add NetworkStatsService polling SSH /proc/net/dev"
```

---

### Task 3: NetworkStatsOverlay Widget

**Files:**
- Create: `app/lib/widgets/network_stats_overlay.dart`

- [ ] **Step 1: Implement the overlay**

```dart
// app/lib/widgets/network_stats_overlay.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/network_stats.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../services/network_stats_service.dart';
import '../services/ssh_service.dart';

class NetworkStatsOverlay extends StatefulWidget {
  const NetworkStatsOverlay({super.key});

  @override
  State<NetworkStatsOverlay> createState() => _NetworkStatsOverlayState();
}

class _NetworkStatsOverlayState extends State<NetworkStatsOverlay> {
  NetworkStatsService? _service;
  NetworkStatsDelta? _delta;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resetService();
  }

  void _resetService() {
    _service?.stop();
    final session = context.read<SessionProvider>().activeSession;
    if (session == null) return;
    _service = NetworkStatsService(
      sessionId: session.id,
      sshService: context.read<SshService>(),
      onUpdate: (delta) => setState(() => _delta = delta),
    );
    _service!.start();
  }

  @override
  void dispose() {
    _service?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    if (!settings.networkStatsEnabled || _delta == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C).withOpacity(0.85),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_downward, size: 12, color: Color(0xFF22C55E)),
          const SizedBox(width: 2),
          Text(
            NetworkStats.formatBytes(_delta!.rxBytesPerSec),
            style: const TextStyle(color: Color(0xFF22C55E), fontSize: 11, fontFamily: 'monospace'),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_upward, size: 12, color: Color(0xFF60A5FA)),
          const SizedBox(width: 2),
          Text(
            NetworkStats.formatBytes(_delta!.txBytesPerSec),
            style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 11, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Add `networkStatsEnabled` to SettingsProvider**

In `app/lib/providers/settings_provider.dart`, add:
```dart
bool networkStatsEnabled = false;
// Include in toJson/fromJson/copyWith
```

- [ ] **Step 3: Add toggle to SettingsScreen**

In `app/lib/widgets/settings_screen.dart`, inside the Terminal section:
```dart
SwitchListTile(
  title: const Text('Network Stats Monitor'),
  subtitle: const Text('Show Rx/Tx overlay on active session'),
  value: settings.networkStatsEnabled,
  onChanged: (v) {
    settings.networkStatsEnabled = v;
    settings.save();
  },
),
```

- [ ] **Step 4: Place overlay in MainScreen**

In `app/lib/widgets/main_screen.dart`, position the overlay in the terminal area using a `Stack`:
```dart
Stack(
  children: [
    const SplitTerminalView(),
    Positioned(
      top: 8,
      right: 8,
      child: const NetworkStatsOverlay(),
    ),
  ],
)
```

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/network_stats_overlay.dart app/lib/providers/settings_provider.dart app/lib/widgets/settings_screen.dart app/lib/widgets/main_screen.dart
git commit -m "feat: add network stats overlay with Rx/Tx per-second display"
```

---

### Task 4: LocalShellService

**Files:**
- Create: `app/lib/services/local_shell_service.dart`
- Create: `app/lib/models/local_session.dart`

- [ ] **Step 1: Implement LocalSession model**

```dart
// app/lib/models/local_session.dart
import 'dart:io';
import 'package:xterm/xterm.dart';
import 'package:uuid/uuid.dart';

enum LocalSessionStatus { running, exited, error }

class LocalSession {
  final String id;
  final Terminal terminal;
  LocalSessionStatus status;
  String? errorMessage;
  Process? _process;

  LocalSession({
    required this.terminal,
    this.status = LocalSessionStatus.running,
  }) : id = const Uuid().v4();

  void attachProcess(Process process) {
    _process = process;
  }

  void kill() {
    _process?.kill();
    status = LocalSessionStatus.exited;
  }
}
```

- [ ] **Step 2: Implement LocalShellService**

```dart
// app/lib/services/local_shell_service.dart
import 'dart:io';
import 'dart:convert';
import 'package:xterm/xterm.dart';
import '../models/local_session.dart';

class LocalShellService {
  final Map<String, LocalSession> _sessions = {};

  Future<LocalSession> openShell() async {
    final terminal = Terminal(maxLines: 10000);
    final session = LocalSession(terminal: terminal);

    final shell = Platform.environment['SHELL'] ?? '/bin/zsh';

    try {
      final process = await Process.start(
        shell,
        [],
        environment: {
          ...Platform.environment,
          'TERM': 'xterm-256color',
        },
        runInShell: false,
      );

      session.attachProcess(process);
      _sessions[session.id] = session;

      // Process stdout -> terminal
      process.stdout.listen((data) {
        terminal.write(utf8.decode(data, allowMalformed: true));
      });

      // Process stderr -> terminal
      process.stderr.listen((data) {
        terminal.write(utf8.decode(data, allowMalformed: true));
      });

      // Terminal input -> process stdin
      terminal.onOutput = (data) {
        process.stdin.add(utf8.encode(data));
      };

      // Handle process exit
      process.exitCode.then((code) {
        session.status = LocalSessionStatus.exited;
        terminal.write('\r\n[Process exited with code $code]\r\n');
      });
    } catch (e) {
      session.status = LocalSessionStatus.error;
      session.errorMessage = e.toString();
    }

    return session;
  }

  void closeSession(String sessionId) {
    _sessions[sessionId]?.kill();
    _sessions.remove(sessionId);
  }

  LocalSession? getSession(String sessionId) => _sessions[sessionId];
}
```

- [ ] **Step 3: Commit**

```bash
git add app/lib/services/local_shell_service.dart app/lib/models/local_session.dart
git commit -m "feat: add LocalShellService and LocalSession for built-in local terminal"
```

---

### Task 5: LocalTerminalScreen Widget

**Files:**
- Create: `app/lib/providers/local_session_provider.dart`
- Create: `app/lib/widgets/local_terminal_screen.dart`

- [ ] **Step 1: Implement LocalSessionProvider**

```dart
// app/lib/providers/local_session_provider.dart
import 'package:flutter/foundation.dart';
import '../models/local_session.dart';
import '../services/local_shell_service.dart';

class LocalSessionProvider extends ChangeNotifier {
  final LocalShellService _service = LocalShellService();
  final List<LocalSession> _sessions = [];
  String? _activeId;

  List<LocalSession> get sessions => List.unmodifiable(_sessions);
  LocalSession? get activeSession =>
      _sessions.where((s) => s.id == _activeId).firstOrNull;

  Future<void> newSession() async {
    final session = await _service.openShell();
    _sessions.add(session);
    _activeId = session.id;
    notifyListeners();
  }

  void setActive(String id) {
    _activeId = id;
    notifyListeners();
  }

  void closeSession(String id) {
    _service.closeSession(id);
    _sessions.removeWhere((s) => s.id == id);
    if (_activeId == id) {
      _activeId = _sessions.isNotEmpty ? _sessions.last.id : null;
    }
    notifyListeners();
  }
}
```

- [ ] **Step 2: Implement LocalTerminalScreen**

```dart
// app/lib/widgets/local_terminal_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';
import '../providers/local_session_provider.dart';
import '../models/local_session.dart';

class LocalTerminalScreen extends StatefulWidget {
  const LocalTerminalScreen({super.key});

  @override
  State<LocalTerminalScreen> createState() => _LocalTerminalScreenState();
}

class _LocalTerminalScreenState extends State<LocalTerminalScreen> {
  @override
  void initState() {
    super.initState();
    // Auto-open first session
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<LocalSessionProvider>();
      if (provider.sessions.isEmpty) {
        provider.newSession();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LocalSessionProvider>();

    return Column(
      children: [
        _buildTabBar(provider),
        Expanded(child: _buildTerminal(provider)),
      ],
    );
  }

  Widget _buildTabBar(LocalSessionProvider provider) {
    return Container(
      height: 36,
      color: const Color(0xFF141414),
      child: Row(
        children: [
          ...provider.sessions.map((s) => _buildTab(s, provider)),
          IconButton(
            icon: const Icon(Icons.add, size: 16, color: Color(0xFF888888)),
            onPressed: provider.newSession,
            tooltip: 'New local shell',
          ),
        ],
      ),
    );
  }

  Widget _buildTab(LocalSession session, LocalSessionProvider provider) {
    final isActive = provider.activeSession?.id == session.id;
    return GestureDetector(
      onTap: () => provider.setActive(session.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1C1C1C) : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isActive ? const Color(0xFF22C55E) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.terminal, size: 14, color: Color(0xFF888888)),
            const SizedBox(width: 6),
            const Text('Local', style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 13)),
            const SizedBox(width: 6),
            InkWell(
              onTap: () => provider.closeSession(session.id),
              child: const Icon(Icons.close, size: 12, color: Color(0xFF555555)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTerminal(LocalSessionProvider provider) {
    final session = provider.activeSession;
    if (session == null) {
      return const Center(
        child: Text('No local session', style: TextStyle(color: Color(0xFF555555))),
      );
    }
    if (session.status == LocalSessionStatus.error) {
      return Center(
        child: Text(
          session.errorMessage ?? 'Unknown error',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
    return TerminalView(terminal: session.terminal);
  }
}
```

- [ ] **Step 3: Register providers and add nav item in main.dart and main_screen.dart**

In `app/lib/main.dart`:
```dart
// Add import:
import 'providers/local_session_provider.dart';
import 'services/local_shell_service.dart';

// Add to MultiProvider:
ChangeNotifierProvider(create: (_) => LocalSessionProvider()),
Provider(create: (_) => LocalShellService()),
```

In `app/lib/widgets/main_screen.dart`, add "Local Terminal" as a navigation item with `Icons.laptop_mac` icon, rendering `LocalTerminalScreen()` when selected.

- [ ] **Step 4: Verify manually**

```bash
cd app && flutter run -d macos
```
1. Click "Local Terminal" in the sidebar.
2. Verify a shell prompt appears.
3. Type `echo hello` and press Enter.
4. Verify "hello" is printed.
5. Click "+" to open a second local shell tab.

- [ ] **Step 5: Commit**

```bash
git add app/lib/providers/local_session_provider.dart app/lib/widgets/local_terminal_screen.dart app/lib/main.dart app/lib/widgets/main_screen.dart
git commit -m "feat: add local terminal screen with multi-tab local shell"
```

---

### Task 6: Tmux Integration

**Files:**
- Modify: `app/lib/providers/settings_provider.dart`
- Modify: `app/lib/services/ssh_service.dart`
- Modify: `app/lib/widgets/settings_screen.dart`

Tmux integration works by modifying the shell command sent when opening an SSH session. Instead of a bare shell, we run `tmux new-session -A -s yourssh` which attaches to an existing tmux session or creates a new one.

- [ ] **Step 1: Add tmuxEnabled to SettingsProvider**

In `app/lib/providers/settings_provider.dart`:
```dart
bool tmuxEnabled = false;
// Add to toJson/fromJson/copyWith/save
```

- [ ] **Step 2: Modify SshService.openShell to prefix with tmux**

In `app/lib/services/ssh_service.dart`, in the `openShell` method, before executing the shell command:

```dart
// Find where the shell is opened, e.g.:
// final shell = await client.shell(...)
// Change to conditionally prefix with tmux:

Future<void> openShell(
  String sessionId, {
  bool useTmux = false,
}) async {
  final client = _clients[sessionId];
  if (client == null) return;

  final shell = await client.shell(
    pty: SSHPtyConfig(
      width: 80,
      height: 24,
      type: 'xterm-256color',
    ),
  );

  if (useTmux) {
    shell.stdin.add(utf8.encode('tmux new-session -A -s yourssh\n'));
  }
  
  // ... rest of existing openShell logic
}
```

- [ ] **Step 3: Pass useTmux from SessionProvider**

In `app/lib/providers/session_provider.dart`, when calling `sshService.openShell`, read the setting:
```dart
final settings = // obtain SettingsProvider reference
await sshService.openShell(
  sessionId,
  useTmux: settings.tmuxEnabled,
);
```

- [ ] **Step 4: Add toggle to SettingsScreen**

In the Connection section of `app/lib/widgets/settings_screen.dart`:
```dart
SwitchListTile(
  title: const Text('Tmux Integration'),
  subtitle: const Text('Attach to tmux session on connect (requires tmux on server)'),
  value: settings.tmuxEnabled,
  onChanged: (v) {
    settings.tmuxEnabled = v;
    settings.save();
  },
),
```

- [ ] **Step 5: Verify manually**

```bash
cd app && flutter run -d macos
```
1. Enable Tmux Integration in Settings.
2. Connect to an SSH server with tmux installed.
3. Verify the session opens inside a tmux environment (status bar visible at bottom).
4. Disconnect and reconnect — verify the same tmux session is reattached.

- [ ] **Step 6: Commit**

```bash
git add app/lib/providers/settings_provider.dart app/lib/services/ssh_service.dart app/lib/providers/session_provider.dart app/lib/widgets/settings_screen.dart
git commit -m "feat: add tmux integration toggle for SSH sessions"
```

---

## Self-Review

**Spec coverage:**
- ✅ Built-in Local Terminal (Tasks 4, 5)
- ✅ Tmux Integration (Task 6)
- ✅ Network Stats Monitor (Tasks 1, 2, 3)

**Gaps:** None — all 3 features addressed.

**Type consistency:** `LocalSession`, `LocalShellService`, `LocalSessionProvider` names consistent across tasks 4–5. `NetworkStats`, `NetworkStatsDelta`, `NetworkStatsService` consistent across tasks 1–3.
