# Docker Panel Completion — Design Spec

**Date:** 2026-06-18  
**Feature:** Docker logs, restart/stop, and Compose awareness for the Containers screen  
**Priority:** P1 (Workflow & integrations)  

---

## Goal

Complete the Docker half of the Containers screen. Currently the screen lists running containers and opens an exec shell. This spec adds:

1. **Docker logs** — inline `docker logs -f` streaming panel (consistent with the existing K8s log panel in `KubernetesPanel`)
2. **Container lifecycle actions** — Stop / Start / Restart buttons per container
3. **Compose awareness** — discover stacks, list services with status, Up/Down stacks, Start/Stop services, per-service log streaming

Kubernetes support (`KubernetesPanel`) is untouched.

---

## Existing code baseline

| File | What it does today |
|------|--------------------|
| `app/lib/models/container_entry.dart` | `ContainerEntry`, `PodEntry`, `RuntimeStatus`, `RuntimeAvailability`, `K8sForwardHandle` |
| `app/lib/services/container_service.dart` | `listDockerContainers`, `detectRuntimes`, `dockerExecCommand`, K8s methods, `streamLogs` (K8s), `startPodPortForward` |
| `app/lib/widgets/containers_screen.dart` | `ContainersScreen` — session picker, Docker/K8s toggle, `_dockerList()` (list + exec), delegates K8s to `KubernetesPanel` |
| `app/lib/widgets/kubernetes_panel.dart` | `KubernetesPanel` — context/namespace, pod list, inline log panel, port-forward |

---

## Architecture

### Tab layout

`ContainersScreen` adds a `compose` tab to the existing enum:

```dart
enum _Tab { docker, compose, kubernetes }
```

The Docker tab renders the new extracted `DockerPanel` widget. The Compose tab renders the new `ComposePanel` widget. `KubernetesPanel` is unchanged.

### File map

| File | Change |
|------|--------|
| `app/lib/models/container_entry.dart` | Add `ComposeStack`, `ComposeService` |
| `app/lib/services/container_service.dart` | Add 8 new methods (Docker actions + Compose) |
| `app/lib/widgets/containers_screen.dart` | Add `_Tab.compose`, render `DockerPanel` / `ComposePanel` |
| `app/lib/widgets/docker_panel.dart` | **New** — container list + log panel + lifecycle actions |
| `app/lib/widgets/compose_panel.dart` | **New** — stack discovery + service list + log panel |
| `app/test/services/container_service_docker_test.dart` | **New** — unit tests for Docker parse/action methods |
| `app/test/services/container_service_compose_test.dart` | **New** — unit tests for Compose parse/discovery methods |

---

## Models

Added to `container_entry.dart`:

```dart
/// One Docker Compose project (from `docker compose ls` or file discovery).
class ComposeStack {
  final String name;        // project name
  final String projectDir;  // absolute path to the directory containing the compose file
  final String status;      // e.g. "running(3)", "exited(1)", "created"

  const ComposeStack({
    required this.name,
    required this.projectDir,
    required this.status,
  });
}

/// One service within a Docker Compose stack (from `docker compose ps`).
class ComposeService {
  final String name;
  final String status;  // e.g. "running", "exited", "created"
  final String image;
  final int replicas;   // number of containers for this service

  const ComposeService({
    required this.name,
    required this.status,
    required this.image,
    this.replicas = 1,
  });
}
```

---

## ContainerService — new methods

All use `ssh.exec` / `ssh.execStream` with `auditSource: 'devops'`. All throw `Exception` on non-zero exit code with the trimmed stderr as the message.

### Docker logs + lifecycle

```dart
/// Streams stdout+stderr from `docker logs -f <id>`.
Stream<String> streamDockerLogs(Host host, String id, {int tail = 100});

/// `docker stop <id>` — throws on failure.
Future<void> stopContainer(Host host, String id);

/// `docker start <id>` — throws on failure.
Future<void> startContainer(Host host, String id);

/// `docker restart <id>` — throws on failure.
Future<void> restartContainer(Host host, String id);
```

`streamDockerLogs` command: `docker logs -f --tail=$tail $id 2>&1`  
(stderr merged into stdout so errors surface in the log panel, not silently dropped.)

### Compose

```dart
/// Discovers Compose stacks: runs `docker compose ls --format json` first,
/// then falls back to a `find` scan of common directories. Results are merged
/// and deduplicated by projectDir.
Future<List<ComposeStack>> discoverComposeStacks(Host host);

/// `cd <projectDir> && docker compose ps --format json` for the given stack.
Future<List<ComposeService>> listComposeServices(Host host, ComposeStack stack);

/// `cd <projectDir> && docker compose up -d`
Future<void> composeUp(Host host, ComposeStack stack);

/// `cd <projectDir> && docker compose down`
Future<void> composeDown(Host host, ComposeStack stack);

/// `cd <projectDir> && docker compose start <service>`
Future<void> startComposeService(Host host, ComposeStack stack, String service);

/// `cd <projectDir> && docker compose stop <service>`
Future<void> stopComposeService(Host host, ComposeStack stack, String service);

/// `cd <projectDir> && docker compose logs -f --tail=$tail <service> 2>&1`
Stream<String> streamComposeServiceLogs(
  Host host, ComposeStack stack, String service, {int tail = 100});
```

All Compose commands `cd` into `stack.projectDir` (single-quoted) before running `docker compose`, which auto-discovers the `docker-compose.yml` / `compose.yml` in that directory. This avoids tracking the exact config-file path (`-f`) per stack — the project directory is enough, and it works identically for `ls`-discovered and `find`-discovered stacks.

### Discovery internals

`discoverComposeStacks` runs two commands concurrently via `Future.wait`:

1. `docker compose ls --format json 2>/dev/null` — returns active/known projects as JSON array `[{Name, Status, ConfigFiles}]`. Requires Docker Compose v2. On parse failure (v1 / missing) returns empty list, not an error.
2. `find ~ /opt /srv /home -maxdepth 3 \( -name "docker-compose.yml" -o -name "compose.yml" \) 2>/dev/null` — collects paths, derives `projectDir = dirname(path)`, `name = basename(projectDir)`, `status = "unknown"`.

Merge: entries from step 1 take precedence; step 2 entries with the same `projectDir` are skipped.

### Static parse functions (testable without SSH)

```dart
static List<ComposeStack> parseComposeLs(String json);
static List<ComposeStack> parseComposeFindOutput(String stdout);
static List<ComposeService> parseComposePs(String json);
```

All are `static` methods — no SSH dependency, fully unit-testable.

---

## DockerPanel widget

New file `app/lib/widgets/docker_panel.dart`. Replaces `_dockerList()` in `ContainersScreen`.

**State:**
```
List<ContainerEntry> _containers
ContainerEntry? _logContainer   // which container's logs are shown
StreamSubscription<String>? _logSub
List<String> _logLines          // capped at 2000 lines (drop oldest)
ScrollController _logScroll
Map<String, bool> _actionLoading  // containerId → loading
String? _actionError
```

**Layout:**

```
┌─────────────────────────────────┐
│ Container list (scrollable)     │  ← always visible
│  [name]  [image · status]       │
│  [Stop] [Restart] [Exec] [Logs] │
├─────────────────────────────────┤  ← visible only when _logContainer != null
│ Logs: <container name>  [Clear] [×]│
│ (streaming log lines)           │
│ (auto-scroll unless user paged) │
└─────────────────────────────────┘
```

**Action button visibility:**
- Container is running (`status` starts with "Up") → show **Stop**, **Restart**, **Exec**, **Logs**
- Container is stopped (`status` starts with "Exited" / "Created") → show **Start**, **Exec** (no Logs — container not running)
- One action in progress per container → that row's buttons disabled

**Log panel behaviour:**
- Opening logs closes any previously open log subscription (`_logSub?.cancel()`)
- Auto-scroll: if the scroll is at the bottom, each new line scrolls down; if the user scrolled up, auto-scroll is paused until they scroll back to the bottom
- Lines capped at 2000; oldest dropped on overflow
- `×` button cancels subscription and hides panel

**Refresh:** container list refreshes after any Stop/Start/Restart completes.

---

## ComposePanel widget

New file `app/lib/widgets/compose_panel.dart`.

**State:**
```
List<ComposeStack> _stacks
ComposeStack? _selectedStack
List<ComposeService> _services
ComposeService? _logService
StreamSubscription<String>? _logSub
List<String> _logLines            // capped at 2000
ScrollController _logScroll
bool _loadingStacks, _loadingServices
String? _error
Map<String, bool> _actionLoading  // key → loading
TextEditingController _manualPathCtrl
```

**Layout:**

```
┌───────────────────────────────────┐
│ [Refresh]  [+ Add path]           │
│ Stack list (scrollable)           │
│  [name]  [status]  [Up] [Down]    │
├───────────────────────────────────┤  ← visible when _selectedStack != null
│ Services in <stack> (scrollable)  │
│  [svc]  [status]  [Start/Stop] [Logs]│
├───────────────────────────────────┤  ← visible when _logService != null
│ Logs: <service>  [Clear] [×]      │
│ (streaming log lines)             │
└───────────────────────────────────┘
```

**Discovery flow:**
1. On mount / Refresh → call `discoverComposeStacks`
2. If no stacks found → show "No Compose stacks found" + a `+` to add a path manually
3. Manual path → call `docker compose -f <path> config --services`; on success, synthesise a `ComposeStack` (projectDir = dirname of the path) and add to list

The ComposePanel is only reached after the screen has confirmed the **docker** runtime is available (the Compose tab gates on `runtimes.docker`, same as the Docker tab). Compose v2 itself is not separately probed: if `docker compose` is missing/v1, `docker compose ls` returns non-zero and discovery degrades to the `find` scan only; any Up/Down/service action then fails with the daemon's own error surfaced in a SnackBar. The manual-path option remains available throughout.

**Stack selection:** tapping a stack row expands service list (calls `listComposeServices`). Tapping again collapses.

**Up/Down:** Up runs `composeUp`, Down runs `composeDown`. Both show a loading spinner on the row, then refresh the stack's status. A non-zero exit surfaces a `SnackBar` with the trimmed stderr (truncated at 200 chars).

**Service Start/Stop:** same pattern — loading per-service, refresh service list on completion, error in SnackBar.

**Log panel:** same auto-scroll / cap / cancel behaviour as `DockerPanel`.

---

## Error handling

| Scenario | Behaviour |
|----------|-----------|
| `docker` not installed | Existing screen-level `_HintCard` with install command (gates both Docker and Compose tabs) |
| `docker compose` not available (v1 / missing) | `docker compose ls` returns non-zero → discovery degrades to `find`-only; actions fail with the daemon error in a SnackBar (no dedicated hint card) |
| Stop/start/restart fails | `SnackBar` with error text; container list refreshed |
| Compose up/down fails | `SnackBar` with truncated stderr (200 chars) |
| Log stream drops | Log panel appends "— connection closed —" as a final line |
| `find` scan errors (missing dirs, permission) | Suppressed via `2>/dev/null`; an empty/failed scan falls through to the manual-path option |

---

## Testing

### `container_service_docker_test.dart`
- `parseDockerPs` already tested — no change
- `streamDockerLogs` command string is correct (`--tail`, `2>&1`)
- `stopContainer` / `startContainer` / `restartContainer`: mock `SshService.exec` returning exit 0 → no throw; exit 1 → throws with stderr

### `container_service_compose_test.dart`
- `parseComposeLs` — valid JSON, empty array, malformed JSON (returns [])
- `parseComposeFindOutput` — paths, dedup, empty output
- `parseComposePs` — valid JSON, empty, unknown field (ignored)
- `discoverComposeStacks` dedup logic — same projectDir from both sources → only one entry

---

## Out of scope

- Docker volume / network management
- `docker pull` / image management
- Docker Compose v1 (`docker-compose` binary) — hint to upgrade, not supported
- Compose watch mode (`docker compose watch`)
- RDP/VNC proxy for containers
