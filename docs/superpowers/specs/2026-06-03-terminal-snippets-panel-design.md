# Terminal Snippets Panel — Design Spec

**Date:** 2026-06-03
**Status:** Approved in discussion, pending written spec review

---

## Goal

Make snippets usable without leaving the terminal screen by adding a dedicated
right-side snippets panel inside the terminal workspace.

The user should be able to:

- stay in the terminal screen
- open or close a snippets panel from terminal UI
- browse and search saved snippets
- run a snippet against the currently active SSH pane
- copy a snippet command without leaving terminal context

---

## Scope Decisions

- **Placement:** a collapsible panel on the **right side** of the terminal area
- **Default state:** **hidden** by default
- **Visibility control:** toggled from terminal toolbar UI
- **Session targeting:** the panel acts on the **currently active pane** in
  split-terminal layouts
- **Runnable target:** only an **active SSH session** is runnable in v1
- **Local terminal behavior:** panel may still render while viewing terminal
  screens, but `Run` is disabled when the active target is not a connected SSH
  session
- **Snippet management in v1:** browse, search, run, copy only
- **Snippet editing in v1:** out of scope; creation/deletion remains in the
  existing Snippets screen

---

## Recommended Approach

Use a **collapsible right panel** integrated into the existing terminal layout.

Why this approach:

- matches the requested interaction model directly
- keeps snippets visible while the user works in shell
- avoids overloading the command palette or input bar
- works cleanly with the current `SplitTerminalView` structure
- is easier to reason about than a floating overlay in a multi-pane terminal

Rejected alternatives:

- **Bottom drawer above input bar:** preserves width, but does not match the
  requested sidebar interaction
- **Floating overlay:** simpler to bolt on, but conflicts with terminal content
  and becomes awkward in split layouts

---

## UX

### Terminal Layout

When terminal view is open, the content area becomes:

```text
┌─────────────────────────────── terminal workspace ───────────────────────────────┬──────────────┐
│                                                                                  │   Snippets   │
│  Broadcast toolbar / terminal toolbar                                            │ search input │
│  ┌────────────────────────────────────────────────────────────────────────────┐    │──────────────│
│  │ active split pane(s)                                                      │    │ snippet list │
│  │                                                                            │    │ Run  Copy    │
│  └────────────────────────────────────────────────────────────────────────────┘    │              │
│  input bar (when enabled)                                                          │              │
└────────────────────────────────────────────────────────────────────────────────────┴──────────────┘
```

### Panel Header

- title: `Snippets`
- search field
- close button

### Snippet Row

Each snippet row shows:

- label
- command preview
- optional tag
- optional short description
- `Run` action
- `Copy` action

### Empty / Disabled States

- no snippets: `No snippets yet`
- search miss: `No snippets match "<query>"`
- no runnable target: `No active SSH pane selected`

---

## Interaction Rules

### Toggle

- panel is hidden on first terminal entry
- user opens it from terminal toolbar
- closing the panel does not affect terminal input bar state

### Active Pane Tracking

- the target session always follows `SessionProvider.activeSession`
- clicking a pane in split terminal changes the runnable target
- panel content does not change by pane, but `Run` eligibility does

### Run

- `Run` sends `snippet.command + "\n"` to the active SSH session
- if there is no connected active SSH session, `Run` is disabled or shows a
  clear non-runnable state

### Copy

- always available
- copies raw snippet command to clipboard

---

## Components

### New

- `app/lib/widgets/terminal_snippets_panel.dart`
  - terminal-specific sidebar UI
  - reads `SnippetProvider`
  - renders search + list + row actions
  - receives target session context from terminal screen state

### Modified

- `app/lib/providers/terminal_layout_provider.dart`
  - add `snippetsPanelVisible`
  - add toggle/set methods

- `app/lib/widgets/broadcast_toolbar.dart` or terminal toolbar owner
  - add snippets toggle button

- `app/lib/widgets/split_terminal_view.dart`
  - wrap terminal area and snippets panel in a `Row`
  - preserve existing terminal panes on the left
  - render snippets panel on the right when visible
  - determine current runnable target from active session

- `packages/yourssh_snippets/lib/src/providers/snippet_provider.dart`
  - reused as the source of snippet data

- existing plugin/snippets terminal bridge
  - reused for `sendInput()` into active SSH session

---

## Data Flow

```text
toolbar button
  -> TerminalLayoutProvider.toggleSnippetsPanel()
  -> SplitTerminalView rebuilds
  -> panel appears on right side

SnippetProvider.snippets
  -> TerminalSnippetsPanel renders searchable list

user clicks terminal pane
  -> SessionProvider.setActive(sessionId)
  -> active session changes
  -> panel run target follows active session

user clicks Run on snippet
  -> resolve SessionProvider.activeSession
  -> validate connected SSH session
  -> sendInput(sessionId, command + "\n")
```

---

## Error Handling

- if active session is `null`, disable `Run`
- if active session is disconnected, disable `Run`
- if `sendInput()` throws, show a terminal-context error message and keep panel
  open
- search should never mutate snippet data

---

## Testing

### Widget

- snippets panel hidden by default
- toolbar toggle shows and hides panel
- panel renders snippets from `SnippetProvider`
- search filters rows correctly
- clicking terminal panes changes the active runnable target
- `Run` sends input to active SSH session only
- `Run` is disabled or guarded when active target is absent/disconnected
- `Copy` copies command

### Integration / Regression

- split terminal still works with panel hidden
- input bar still works when panel is visible
- broadcast mode behavior remains unchanged unless explicitly extended later

---

## Out of Scope

- editing snippets from terminal panel
- creating/deleting snippets from terminal panel
- local shell snippet execution
- per-pane snippet history
- drag-resize for snippets panel
- persistence of panel width or visibility preference

---

## Acceptance Criteria

- terminal screen has a snippets toggle in toolbar
- opening the toggle shows a right-side snippets panel
- panel can search and list saved snippets
- running a snippet sends it to the currently active SSH pane
- user no longer needs to leave terminal view to execute a snippet
