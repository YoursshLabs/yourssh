# Test Connection Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "TEST CONNECTION" button to the Host Detail Panel and host cards that performs a full TCP + SSH auth check and shows the result inline.

**Architecture:** A new `testConnection()` method on `SshService` does the work (connect, auth, close immediately). `HostDetailPanel` gets a TEST CONNECTION button with inline result above the CONNECT button. `_HostCard` in the dashboard gets a TEST icon button on hover with a timed inline result badge.

**Tech Stack:** Flutter/Dart, dartssh2 (`SSHSocket`, `SSHClient`), provider

---

## File Map

| File | Change |
|---|---|
| `app/lib/services/ssh_service.dart` | Add `testConnection()` method |
| `app/lib/widgets/host_detail_panel.dart` | Add TEST CONNECTION button + result row; uppercase SAVE ONLY |
| `app/lib/widgets/hosts_dashboard.dart` | Add TEST button + result on `_HostCard` |

---

### Task 1: Add `testConnection()` to `SshService`

**Files:**
- Modify: `app/lib/services/ssh_service.dart`

- [ ] **Step 1: Add the method** — insert after the `connect()` method (after line 51):

```dart
Future<({bool success, int latencyMs, String? error})> testConnection(
  Host host, {
  String? password,
  SshKeyEntry? keyEntry,
}) async {
  final stopwatch = Stopwatch()..start();
  SSHClient? client;
  try {
    final socket = await SSHSocket.connect(host.host, host.port)
        .timeout(const Duration(seconds: 10));

    List<SSHKeyPair> identities = [];
    if (host.authType == AuthType.privateKey && keyEntry != null) {
      final keyFile = File(keyEntry.privateKeyPath);
      if (await keyFile.exists()) {
        final pem = await keyFile.readAsString();
        final passphrase = await _storage.loadPassphrase(keyEntry.id);
        identities = SSHKeyPair.fromPem(pem, passphrase ?? '');
      }
    }

    client = SSHClient(
      socket,
      username: host.username,
      onPasswordRequest: () => password ?? '',
      identities: identities.isNotEmpty ? identities : null,
      onVerifyHostKey: (_, __) async => true,
    );
    await client.authenticated.timeout(const Duration(seconds: 10));
    stopwatch.stop();
    return (success: true, latencyMs: stopwatch.elapsedMilliseconds, error: null);
  } on TimeoutException {
    return (success: false, latencyMs: 0, error: 'Host unreachable');
  } on SocketException {
    return (success: false, latencyMs: 0, error: 'Host unreachable');
  } catch (e) {
    final msg = e.toString();
    final isAuth = msg.toLowerCase().contains('auth') ||
        msg.toLowerCase().contains('permission denied') ||
        msg.toLowerCase().contains('userauth');
    return (
      success: false,
      latencyMs: 0,
      error: isAuth
          ? 'Authentication failed'
          : (msg.length > 80 ? '${msg.substring(0, 80)}…' : msg),
    );
  } finally {
    client?.close();
  }
}
```

- [ ] **Step 2: Add missing import** — `dart:async` is already imported (`dart:async` provides `TimeoutException`). Confirm `dart:io` is imported (it is, line 3). No new imports needed.

- [ ] **Step 3: Analyze**

```bash
cd app && flutter analyze lib/services/ssh_service.dart
```
Expected: `No issues found`

- [ ] **Step 4: Commit**

```bash
git add app/lib/services/ssh_service.dart
git commit -m "feat: add testConnection() to SshService"
```

---

### Task 2: TEST CONNECTION button in `HostDetailPanel`

**Files:**
- Modify: `app/lib/widgets/host_detail_panel.dart`

- [ ] **Step 1: Add state fields** — in `_HostDetailPanelState`, after `bool _saving = false;`:

```dart
bool _testing = false;
({bool success, int latencyMs, String? error})? _testResult;
```

- [ ] **Step 2: Add field-change listeners to reset result** — in `initState()`, after `_authType = h?.authType ?? AuthType.password;`:

```dart
for (final c in [_hostCtrl, _portCtrl, _usernameCtrl, _passwordCtrl]) {
  c.addListener(_clearTestResult);
}
```

- [ ] **Step 3: Add `_clearTestResult` method** — after `dispose()`:

```dart
void _clearTestResult() {
  if (_testResult != null) setState(() => _testResult = null);
}
```

Also call `_clearTestResult()` when auth type or key selection changes. Update the two `setState` calls that set `_authType` and `_selectedKeyId`:

```dart
// In the AuthType dropdown onChanged:
onChanged: (v) => setState(() { _authType = v!; _selectedKeyId = null; _testResult = null; }),

// In the key dropdown onChanged:
onChanged: (v) => setState(() { _selectedKeyId = v; _testResult = null; }),
```

- [ ] **Step 4: Remove the listeners in `dispose()`** — inside the existing loop:

```dart
@override
void dispose() {
  for (final c in [_hostCtrl, _labelCtrl, _groupCtrl, _tagsCtrl, _portCtrl, _usernameCtrl, _passwordCtrl]) {
    c.dispose();
  }
  // Note: listeners added to _hostCtrl, _portCtrl, _usernameCtrl, _passwordCtrl
  // are automatically removed when the controller is disposed above.
  super.dispose();
}
```

No change needed — `TextEditingController.dispose()` removes all listeners automatically.

- [ ] **Step 5: Add `_test()` method** — after `_connect()`:

```dart
Future<void> _test() async {
  if (_formKey.currentState?.validate() != true) return;
  setState(() { _testing = true; _testResult = null; });

  final keys = context.read<KeyProvider>().keys;
  final keyEntry = _authType == AuthType.privateKey && _selectedKeyId != null
      ? keys.where((k) => k.id == _selectedKeyId).firstOrNull
      : null;

  final host = Host(
    id: widget.existing?.id,
    label: _hostCtrl.text.trim(),
    host: _hostCtrl.text.trim(),
    port: int.tryParse(_portCtrl.text) ?? 22,
    username: _usernameCtrl.text.trim(),
    authType: _authType,
    keyId: _authType == AuthType.privateKey ? _selectedKeyId : null,
    group: '',
    tags: const [],
  );

  final result = await context.read<SshService>().testConnection(
    host,
    password: _passwordCtrl.text,
    keyEntry: keyEntry,
  );

  if (mounted) setState(() { _testing = false; _testResult = result; });
}
```

- [ ] **Step 6: Add import for `SshService`** — at the top of `host_detail_panel.dart`, add:

```dart
import '../services/ssh_service.dart';
```

- [ ] **Step 7: Replace the button area** — find this block (around line 236) and replace:

```dart
// OLD:
                const SizedBox(height: 24),
                // Connect button
                GestureDetector(
                  onTap: _saving ? null : _connect,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: _saving ? AppColors.accentDim : AppColors.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                        : const Text('CONNECT', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 1)),
                  ),
                ),
                const SizedBox(height: 8),
                // Save without connecting
                GestureDetector(
                  onTap: _saving ? null : _save,
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    alignment: Alignment.center,
                    child: const Text('Save only', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ),
                ),
```

Replace with:

```dart
                const SizedBox(height: 24),
                // Test connection button + result
                GestureDetector(
                  onTap: (_testing || _saving) ? null : _test,
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    alignment: Alignment.center,
                    child: _testing
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.textSecondary)),
                              SizedBox(width: 8),
                              Text('TESTING…', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, letterSpacing: 0.5)),
                            ],
                          )
                        : const Text('TEST CONNECTION', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, letterSpacing: 0.5)),
                  ),
                ),
                if (_testResult != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _testResult!.success
                          ? AppColors.accent.withValues(alpha: 0.08)
                          : AppColors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _testResult!.success ? AppColors.accent.withValues(alpha: 0.3) : AppColors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _testResult!.success ? Icons.check_circle_outline : Icons.error_outline,
                          size: 14,
                          color: _testResult!.success ? AppColors.accent : AppColors.red,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _testResult!.success
                                ? 'Connected · ${_testResult!.latencyMs}ms'
                                : _testResult!.error ?? 'Failed',
                            style: TextStyle(
                              color: _testResult!.success ? AppColors.accent : AppColors.red,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                // Connect button
                GestureDetector(
                  onTap: _saving ? null : _connect,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: _saving ? AppColors.accentDim : AppColors.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                        : const Text('CONNECT', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 1)),
                  ),
                ),
                const SizedBox(height: 8),
                // Save without connecting
                GestureDetector(
                  onTap: _saving ? null : _save,
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    alignment: Alignment.center,
                    child: const Text('SAVE ONLY', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, letterSpacing: 0.5)),
                  ),
                ),
```

- [ ] **Step 8: Analyze**

```bash
cd app && flutter analyze lib/widgets/host_detail_panel.dart
```
Expected: `No issues found`

- [ ] **Step 9: Commit**

```bash
git add app/lib/widgets/host_detail_panel.dart
git commit -m "feat: add TEST CONNECTION button to HostDetailPanel, uppercase SAVE ONLY"
```

---

### Task 3: TEST button on host cards in dashboard

**Files:**
- Modify: `app/lib/widgets/hosts_dashboard.dart`

- [ ] **Step 1: Add imports** — at the top of `hosts_dashboard.dart`, add:

```dart
import 'dart:async';
import '../models/ssh_key.dart';
import '../providers/key_provider.dart';
import '../services/ssh_service.dart';
```

- [ ] **Step 2: Add state fields to `_HostCardState`** — after `bool _hovered = false;`:

```dart
bool _testing = false;
({bool success, int latencyMs, String? error})? _testResult;
Timer? _resultTimer;
```

- [ ] **Step 3: Override dispose to cancel timer** — add after the existing `_HostCardState` fields:

```dart
@override
void dispose() {
  _resultTimer?.cancel();
  super.dispose();
}
```

- [ ] **Step 4: Add `_test()` method** — add before `_iconBtn()` in `_HostCardState`:

```dart
Future<void> _test() async {
  if (_testing) return;
  _resultTimer?.cancel();
  setState(() { _testing = true; _testResult = null; });

  final sshService = context.read<SshService>();
  final storage = context.read<StorageService>();
  final keys = context.read<KeyProvider>().keys;

  final password = widget.host.authType == AuthType.password
      ? await storage.loadPassword(widget.host.id)
      : null;

  SshKeyEntry? keyEntry;
  if (widget.host.authType == AuthType.privateKey && widget.host.keyId != null) {
    keyEntry = keys.where((k) => k.id == widget.host.keyId).firstOrNull;
  }

  final result = await sshService.testConnection(
    widget.host,
    password: password,
    keyEntry: keyEntry,
  );

  if (!mounted) return;
  setState(() { _testing = false; _testResult = result; });
  _resultTimer = Timer(const Duration(seconds: 8), () {
    if (mounted) setState(() => _testResult = null);
  });
}
```

- [ ] **Step 5: Update `_HostCardState.build()` to show TEST button and result** — replace the action buttons block:

```dart
// OLD:
              // Action buttons (show on hover)
              if (_hovered) ...[
                _iconBtn(Icons.folder_outlined, 'SFTP', onTap: () => _openSftp(context)),
                const SizedBox(width: 2),
                _iconBtn(Icons.more_horiz, 'More', onTapDown: (d) => _showMenu(context, hostProvider, sessionProvider, d.globalPosition)),
              ],
```

Replace with:

```dart
              // Action buttons (show on hover)
              if (_hovered && !_testing && _testResult == null) ...[
                _iconBtn(Icons.network_check, 'Test Connection', onTap: _test),
                const SizedBox(width: 2),
                _iconBtn(Icons.folder_outlined, 'SFTP', onTap: () => _openSftp(context)),
                const SizedBox(width: 2),
                _iconBtn(Icons.more_horiz, 'More', onTapDown: (d) => _showMenu(context, hostProvider, sessionProvider, d.globalPosition)),
              ],
              if (_testing)
                const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.textSecondary),
                ),
              if (_testResult != null) ...[
                Icon(
                  _testResult!.success ? Icons.check_circle_outline : Icons.error_outline,
                  size: 14,
                  color: _testResult!.success ? AppColors.accent : AppColors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  _testResult!.success
                      ? '${_testResult!.latencyMs}ms'
                      : _testResult!.error ?? 'Failed',
                  style: TextStyle(
                    color: _testResult!.success ? AppColors.accent : AppColors.red,
                    fontSize: 11,
                  ),
                ),
              ],
```

- [ ] **Step 6: Analyze**

```bash
cd app && flutter analyze lib/widgets/hosts_dashboard.dart
```
Expected: `No issues found`

- [ ] **Step 7: Full analyze**

```bash
cd app && flutter analyze
```
Expected: `No issues found`

- [ ] **Step 8: Commit**

```bash
git add app/lib/widgets/hosts_dashboard.dart
git commit -m "feat: add TEST button to host cards in dashboard"
```
