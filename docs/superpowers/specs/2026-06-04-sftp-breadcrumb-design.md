# SFTP Breadcrumb Navigation — Design (issue #41)

Date: 2026-06-04
Status: approved

## Problem

The remote SFTP panel (`sftp_panel.dart`) shows the current path as static,
ellipsized text with only an "Up" button, making it tedious to jump back
several directory levels. The local panel (`local_file_panel.dart`) already
has a clickable breadcrumb, but it is implemented inline and not reusable.

## Design

### New shared widget: `PathBreadcrumb`

`app/lib/widgets/path_breadcrumb.dart`

- A horizontal, scrollable row of clickable path segments — exactly the crumb
  row portion of the local panel's existing breadcrumb (separator chevrons,
  last crumb highlighted `#D4D4D4` w500, others `#666666`).
- API:
  - `crumbs: List<PathCrumb>` where `PathCrumb = ({String label, String path})`
  - `onNavigate: ValueChanged<String>` — called with the crumb's `path`
- Owns no navigation logic or platform knowledge; each panel embeds it in its
  own bar (back/forward, Up, host chip, toolbar buttons stay panel-specific).

### Pure helper: `posixCrumbs(String path)`

Top-level function in the same file. Splits a POSIX path into crumbs with a
leading root crumb `(label: '/', path: '/')`. Used by the remote panel
(remote paths are always POSIX). Handles `/`, nested paths, and trailing
slashes.

### Remote panel (`sftp_panel.dart`)

In `_buildPathBar`, replace `Expanded(child: Text(prov.currentPath))` with
`Expanded(child: PathBreadcrumb(...))`. Crumb tap → `_loadDirectory(path)`.
The Up button, host chip, `root` badge, and toolbar buttons are unchanged.

### Local panel (`local_file_panel.dart`)

Refactor `_buildBreadcrumb` to embed the shared `PathBreadcrumb`. The
platform-aware crumb building (`Windows` drive paths, `Macintosh HD` root
label) stays in the local panel and is passed in as data. No behavior change.

## Testing

- Unit: `posixCrumbs` — root, nested path, trailing slash.
- Widget: `PathBreadcrumb` renders all crumbs, tap fires `onNavigate` with the
  segment's path, last crumb styled as current.

## Out of scope

- Back/forward history for the remote panel.
- Editable path field (type-to-navigate).
