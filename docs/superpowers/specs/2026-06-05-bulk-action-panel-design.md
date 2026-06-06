# Bulk Action Panel — Design

**Date:** 2026-06-05
**Status:** Approved

## Problem

Roadmap P0 #1. Managing 10–100+ hosts means repeating the same operation
host by host: opening tabs one at a time, running the same diagnostic
command on each, copying a config file to a fleet, or eyeballing outputs to
spot the host that drifted. The app has all the per-host primitives —
`SessionProvider.connect`, `SshService.exec` (auto-connects via
`ensureClient`, no shell needed), `SftpTransferService.uploadFile` /
`uploadDirectory` — but no way to select N hosts and apply an action to all
of them.

## Goals

- Multi-select hosts on the dashboard (selection mode, filter-aware
  select-all).
- **Connect all** — open session tabs for every selected host.
- **Run command** — execute one command (free text or snippet) on N hosts
  in parallel; per-host results table plus a **Diff** view that groups
  identical outputs and answers "which host differs from the fleet?".
- **Push files** — upload local files or a folder to the same remote path
  on N hosts, with per-host progress and cancel.
- Per-host failure isolation: one unreachable host never aborts the batch.
- Engine testable with fakes — no real SSH in unit tests.

## Non-goals

- Audit log persistence of bulk runs (roadmap P0 #2 — the engine's
  per-host result stream is the future hook point, but nothing is written
  to disk now).
- Interactive auth mid-batch (no password/TOFU prompts per host; hosts
  without stored credentials or a trusted host key fail with a clear
  per-host error).
- Templated/parameterized commands per host (roadmap "parameterized
  workflows" covers that).
- Scheduling, dry-run, or rollback semantics.
- Bulk edit of host settings (different feature).

## Selection mode (hosts dashboard)

State lives in `_HostsDashboardState` (no provider — nothing outside the
dashboard consumes it): `bool _selectionMode`, `Set<String> _selectedHostIds`.

- A **Select** button on the top bar enters selection mode.
- In mode:
  - Every `_HostCard` shows a checkbox in the top-left corner; a single
    click anywhere on the card toggles selection (double-tap connect is
    disabled while in mode). Selected cards get an accent border.
  - The top bar becomes an action bar: `N selected` · **Select all**
    (selects every host matching the *current* filter/`HostQuery`, so
    `tag:prod` + Select all selects the prod fleet) · **Clear** · action
    buttons **Connect all / Run command / Push files** · **Done**.
  - **Esc** exits the mode and clears the selection.
  - Hosts deleted while selected are pruned from the set on build.
- Outside the mode the dashboard behaves exactly as today.

Diff is **not** a separate action: it is a tab inside the Run command
results (one run, two views), so the command never executes twice.

## Connect all (direct action, no dialog)

- For each selected host call `SessionProvider.connect(host)` — existing
  per-tab status, error display, and auto-reconnect already cover the
  result UX.
- Hosts that already have a session in `connecting`/`connected` state are
  skipped; a snackbar reports `Opened 5 tabs · 2 already connected`.
- When N > 5, confirm first ("Open N tabs?").
- Exits selection mode when done.

## Engine: `BulkActionService` (new, `app/lib/services/bulk_action_service.dart`)

Pure orchestration over injected functions — tests inject fakes:

```dart
BulkActionService({
  required Future<({String stdout, String stderr, int exitCode})> Function(
      Host host, String command) exec,                  // SshService.exec
  required Future<void> Function(Host host, String localPath,
      String remotePath) uploadFile,                    // SftpTransferService.uploadFile
  required Future<void> Function(Host host, String localDir,
      String remoteDir, {void Function(int sent, int total)? onProgress,
      bool Function()? isCancelled}) uploadDirectory,   // SftpTransferService.uploadDirectory
  required Future<void> Function(Host host, String path) mkdirRecursive,
});

Future<void> runCommand(List<Host> hosts, String command,
    {required void Function(BulkHostResult) onUpdate,
     required BulkCancelToken token,
     int maxConcurrent = 6,
     Duration perHostTimeout = const Duration(seconds: 30)});

Future<void> pushFiles(List<Host> hosts, List<String> localPaths,
    String remoteDir,
    {required void Function(BulkHostResult) onUpdate,
     required BulkCancelToken token,
     int maxConcurrent = 4});
```

- **Worker pool**: bounded concurrency over a queue (default 6 for exec,
  4 for transfers). Selecting 50 hosts must not open 50 simultaneous SSH
  handshakes.
- **Per-host timeout** (exec only): 30 s wrapping connect+exec; an
  unreachable host becomes `failed: timed out` instead of hanging the
  batch. Transfers have no timeout — they show live progress and are
  cancellable.
- **`BulkCancelToken`** (`bool cancelled` + `cancel()`): queued hosts
  become `cancelled`; hosts already in flight run to completion and record
  their real result (exec cannot be aborted mid-flight).
- **Failure isolation**: every per-host exception is caught and recorded
  on that host's result; the pool moves on.
- `pushFiles` resolves each local path: directories go through
  `uploadDirectory` (landing at `remoteDir/<dirname>`), files through
  `uploadFile` (landing at `remoteDir/<filename>`). Before uploading to a
  host it calls `mkdirRecursive(host, remoteDir)` (ignore
  already-exists). Files within one host upload sequentially; hosts run in
  parallel.

## Results model (`app/lib/models/bulk_result.dart`)

```dart
enum BulkHostStatus { pending, running, success, failed, cancelled }

class BulkHostResult {
  final Host host;
  final BulkHostStatus status;
  final int? exitCode;          // exec only
  final String stdout;          // exec only
  final String stderr;          // exec only
  final String? error;          // connect/auth/timeout/transfer error
  final Duration? elapsed;
  final int bytesTransferred;   // push only
  final int totalBytes;         // push only
}
```

Success for exec means the command ran — a non-zero `exitCode` is still
`success` (the command's own failure is data, shown in the row); `failed`
means the app could not run it (connect, auth, timeout, channel error).

## `BulkRunController` (ChangeNotifier, dialog-scoped)

Created by the dialog, disposed with it — **not** registered in
`main.dart`'s `MultiProvider`, because the run only lives as long as the
dialog and nothing else consumes it. Holds the host→`BulkHostResult` map,
`isRunning`, the summary counts, and `cancel()`. Closing the dialog while
running prompts "Cancel run?" and cancels the token on confirm.

## Run command dialog (`app/lib/widgets/bulk/bulk_run_dialog.dart`, modal ≈900×650)

- Header: command field (free text) + snippet picker button (picking a
  snippet fills the field — snippets are a shortcut, not a gate) + host
  count + **Run**.
- **Results tab**: one row per host — status dot
  (pending/running/success/failed/cancelled), exit code, duration, first
  line of output; expanding a row shows full stdout/stderr/error. Footer:
  `12 ok · 2 failed · 1 cancelled` + **Run again** / **Cancel**.
- **Diff tab** (enabled when the run finishes):
  - Successful results are grouped by identical stdout (exact match after
    trimming trailing whitespace). Header: "3 distinct outputs". The
    largest group is the default **baseline**. Each group shows its host
    count and first few host names; selecting a group shows its output,
    and non-baseline groups show a colored unified diff against the
    baseline. Any group can be promoted to baseline.
  - **Compare two hosts**: two host dropdowns → side-by-side two-column
    view with changed lines highlighted (driven by the same line-diff
    result).
  - Failed hosts are excluded from grouping and listed under a separate
    "Failed" section.

## Push files dialog (`app/lib/widgets/bulk/bulk_push_dialog.dart`)

- Source: multiple files **or** one folder via the OS picker
  (`file_selector`; add the dependency if absent).
- Destination: one absolute remote path applied to every host.
- Existing remote files are overwritten — the dialog says so.
- Per-host progress bar (bytes) + overall progress + cancel (wired to the
  service's `isCancelled` callback). Shares the per-host row list widget
  with the run dialog (`bulk_host_status_list.dart`).
- `SftpTransferService.uploadFile` gains an optional
  `onProgress(sent, total)` callback (today only `uploadDirectory` reports
  progress) so single-file pushes show bytes too.
- `SftpTransferService.uploadDirectory` gains an `overwrite` flag
  (default `false` keeps today's skip-existing behavior; bulk push passes
  `true` so the fleet converges on the pushed content).

## Diff logic (pure, `app/lib/util/bulk_diff.dart`)

No Flutter or IO imports:

- `List<OutputGroup> groupByOutput(List<BulkHostResult>)` — exact-match
  grouping on trimmed stdout, sorted by group size descending.
- `List<DiffLine> lineDiff(String a, String b)` — minimal line-based LCS
  diff (~80 lines, no new dependency); each `DiffLine` is
  `same | added | removed`, consumed by both the unified and the
  side-by-side renderers.

## Error handling

- Per-host isolation everywhere; the row shows a truncated error, expand
  shows the full text.
- `SshService.exec` auto-connects with stored credentials via
  `ensureClient`; hosts needing interactive auth or first-time host-key
  trust fail with that error message — the batch never pops dialogs.
- Cancel semantics as above (queued → cancelled, in-flight → real result).

## Testing

- `test/services/bulk_action_service_test.dart` (fake exec/upload fns):
  concurrency cap respected (assert max observed in-flight), all results
  collected, one throwing host doesn't affect others, cancel marks queued
  hosts cancelled and stops dequeuing, timeout produces `failed`,
  `pushFiles` calls mkdir before upload and routes files vs directories
  correctly.
- `test/util/bulk_diff_test.dart`: grouping (identical, distinct, trailing
  whitespace, empty output), baseline = largest group, line diff on
  add/remove/change/empty cases.
- Widget test for selection mode: toggle, card click selects, select-all
  respects the active filter, Esc clears.

## New / changed files

| File | Change |
|---|---|
| `app/lib/services/bulk_action_service.dart` | new — engine |
| `app/lib/models/bulk_result.dart` | new — result model + status enum |
| `app/lib/util/bulk_diff.dart` | new — pure grouping + LCS line diff |
| `app/lib/widgets/bulk/bulk_run_dialog.dart` | new — run command UI |
| `app/lib/widgets/bulk/bulk_push_dialog.dart` | new — push files UI |
| `app/lib/widgets/bulk/bulk_host_status_list.dart` | new — shared per-host rows |
| `app/lib/widgets/bulk/bulk_diff_view.dart` | new — diff tab (groups + side-by-side) |
| `app/lib/widgets/hosts_dashboard.dart` | selection mode + action bar |
| `app/lib/services/sftp_transfer_service.dart` | `uploadFile` gains optional `onProgress`; `uploadDirectory` gains `overwrite` flag |
| `app/pubspec.yaml` | no change — `file_selector` is already a dependency |
