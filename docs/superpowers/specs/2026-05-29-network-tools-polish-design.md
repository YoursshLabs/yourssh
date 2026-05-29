# Network Tools Polish — Design Spec

**Date:** 2026-05-29
**Scope:** `devops_tools_screen.dart` + `tool_result_view.dart`

---

## Goal

Polish the Network Tools screen to be visually consistent with the DevOps hub and more useful via multi-tab results.

---

## Changes

### 1. Sidebar — Grouped, consistent style

Replace the current `ListView` of `ListTile` widgets with the same `_SubNavItem` pattern used in `devops_hub_screen.dart` (hover state, accent border when active, icon + label).

Group the 12 tools into three labelled sections with a small uppercase header (same as hub):

| Section | Tools |
|---|---|
| **Network** | Ping, cURL, DNS Lookup, Traceroute, Port Scan, Whois, Netstat |
| **System** | Disk Usage, Top Processes, Memory Info |
| **HTTP** | HTTP Headers, SSL Certificate |

Section headers use the same `textTertiary / 10px / w600 / letterSpacing 0.8` style as the hub.

### 2. Multi-tab results

Each press of **Run** appends a new tab. The new tab becomes active immediately.

**Tab model — `_ResultTab`:**
```dart
class _ResultTab {
  final String id;       // uuid or incrementing int as string
  final String label;    // "$toolName $input" truncated to 24 chars
  ToolResult? result;    // null while loading
  bool isLoading;
}
```

**Tab bar** sits between the toolbar and the output area:
- Tabs are scrollable horizontally if they overflow
- Each tab shows label + ✕ close button
- Active tab has `accent` bottom border
- A `+` placeholder at the end (tapping it does nothing — tabs auto-open on Run)
- **Clear all** icon button (`Icons.clear_all`) in the toolbar clears every tab

**Empty state** (no tabs yet): keep existing "Run a tool to see output" centered text inside `ToolResultView`.

### 3. ToolResultView — no changes needed

`ToolResultView` already has: copy button, success/error status with duration, selectable monospace output. No changes required.

### 4. Toolbar — add Clear all

Add `IconButton(Icons.clear_all)` to the toolbar row (right of Run button), enabled only when `_tabs.isNotEmpty`. Clears `_tabs` and resets `_activeTabIndex` to -1.

---

## State

`_DevopsToolsScreenState` gains:

```dart
final List<_ResultTab> _tabs = [];
int _activeTabIndex = -1;

void _run() async {
  // create new tab with isLoading=true, append, set active
  // run tool
  // update tab.result, tab.isLoading=false
  // call setState
}

void _closeTab(int index) {
  // remove tab, clamp activeTabIndex
}

void _clearAllTabs() {
  // clear list, reset index
}
```

---

## File changes

| File | Change |
|---|---|
| `devops_tools_screen.dart` | Grouped sidebar, tab state, tab bar, clear-all button |
| `tool_result_view.dart` | No changes |

---

## What stays the same

- All 12 tools and their SSH exec logic
- Input field + hint per tool
- `ToolResultView` layout and copy behaviour
- Session-required warning banner
