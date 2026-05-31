# Docker / Kubernetes Exec — Design

**Date:** 2026-05-31
**Status:** Approved (pending spec review)

## Goal

Let the user list Docker containers and Kubernetes pods running on a remote
host (over an existing SSH connection) and exec directly into them, each in a
fresh terminal tab. Lives inside the DevOps plugin.

## Decisions (from brainstorming)

- **Scope:** Docker **and** Kubernetes.
- **Placement:** New sub-screen in the DevOps plugin hub.
- **Exec model:** Opens a **new SSH session tab** that runs the exec command
  on shell start (full xterm terminal, isolated from the host shell).
- **Source:** Lists against an **already-open SSH session** chosen from a
  dropdown (uses `SshService.exec` against that session's host).
- **Missing runtime:** When `docker`/`kubectl` is not installed (or not
  permitted), show an **install/fix hint** tailored to `host.detectedOs`,
  with a copy button.

## Architecture

App-side screen passed into the DevOps plugin via a new `DevOpsPluginConfig`
slot, following the existing pattern (`networkToolsScreen`, etc.). This is
required because opening a new terminal tab needs `SessionProvider` /
`SshService`, which the plugin package intentionally cannot depend on.

```
ContainersScreen (app/lib/widgets)
  ├── SessionProvider        — pick active session, open exec tab
  ├── ContainerService       — list + parse docker/kubectl output, detect runtimes
  │     └── SshService.exec(host, cmd)
  └── models: ContainerEntry, PodEntry, RuntimeStatus
```

## Components

### 1. Models — `app/lib/models/container_entry.dart`

```
class ContainerEntry { String id; String name; String image; String status; }

class PodEntry {
  String name; String namespace; String ready; String status;
  List<String> containers;   // pod may have >1 container → pick on exec
}

enum RuntimeAvailability { available, notInstalled, noPermission }

class RuntimeStatus {
  RuntimeAvailability docker;
  RuntimeAvailability kubectl;
}
```

### 2. `ContainerService` — `app/lib/services/container_service.dart`

- `Future<RuntimeStatus> detectRuntimes(Host host)`
  - `command -v docker` / `command -v kubectl` to distinguish
    `notInstalled`; a non-zero `docker ps` with a permission-denied stderr
    maps to `noPermission`.
- `Future<List<ContainerEntry>> listDockerContainers(Host host)`
  - `docker ps --format '{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}'`, split
    on `|`, one entry per line.
- `Future<List<PodEntry>> listPods(Host host, {String? namespace, bool allNamespaces = false})`
  - `kubectl get pods` with `-n <ns>` or `-A`, custom-columns / parse the
    standard tabular output; containers resolved per-pod when needed for exec.
- Pure parsing helpers split out from the SSH calls so they are unit-testable
  without a connection.

### 3. `ContainersScreen` — `app/lib/widgets/containers_screen.dart`

- **Top bar:** dropdown of active sessions (`SessionProvider.sessions`) +
  Refresh button.
- **Sub-tabs:** Docker / Kubernetes — only shown for runtimes that are
  `available`.
- **Kubernetes controls:** namespace text field (default `default`) +
  "All namespaces" toggle (`-A`).
- **List rows:** name / image (or ready) / status + an **Exec** button.
  - Pod with multiple containers → small picker before exec.
- **States:**
  - No active session → prompt to open an SSH session first.
  - Runtime `notInstalled` → install hint (see below).
  - Runtime `noPermission` → fix hint (e.g. `sudo usermod -aG docker $USER`).
  - Command error → show stderr.

### 4. Install / fix hints

Tailored to `host.detectedOs`:

- **Docker**
  - Debian/Ubuntu: `curl -fsSL https://get.docker.com | sh`
  - Otherwise: link to official install docs.
  - `noPermission`: `sudo usermod -aG docker $USER` (then re-login).
- **kubectl**
  - Per-OS package command (`apt` / `dnf` / `brew`) or the official `curl`
    install line.

Each hint is shown with a **copy** button. (Running the install command
directly in the active session is deferred — copy only for the first cut.)

### 5. Exec → new terminal tab

- Add an optional `initialCommand` to `SshSession` (and `openShell`). After
  the shell opens, if set, `shell.write(cmd + '\n')` — same mechanism already
  used for the `tmux` auto-attach.
- `SessionProvider.connect(host, {String? initialCommand})` opens a new tab
  that runs straight into the container.
- **Docker exec command:**
  `docker exec -it <id> sh -c 'command -v bash >/dev/null && exec bash || exec sh'`
  (bash with sh fallback).
- **Kubernetes exec command:**
  `kubectl exec -it <pod> -n <ns> -c <container> -- sh -c '...'`
  (same bash→sh fallback).

### 6. Wiring

- Add `final Widget containersScreen;` to `DevOpsPluginConfig`.
- Add `_DevOpsTool.containers` (icon `Icons.widgets_outlined`, label
  "Containers") to `devops_hub_screen.dart` sub-nav + content switch.
- Register `containersScreen: const ContainersScreen()` in
  `plugin_registry.dart`.

## Testing (TDD)

- Unit tests for `ContainerService` parsers: sample `docker ps` output →
  expected `ContainerEntry` list; sample `kubectl get pods` output (single +
  all-namespaces) → expected `PodEntry` list; empty output → empty list;
  malformed line tolerated.
- `detectRuntimes` mapping: missing command → `notInstalled`;
  permission-denied stderr → `noPermission`.

## Out of scope (deferred)

- Container logs / stop / restart actions (Exec only for v1).
- Running install commands directly (copy hint only).
- `sudo docker` toggle (hint only for now).
- Auto-refresh / live status polling.
```
