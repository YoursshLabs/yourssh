# Context

**Spike.** forui 0.27.7 needs Flutter >=3.47 and Dart >=3.13. The app now builds on Flutter 3.50.0 (CI pins it). The throwaway spike lives in the session scratchpad.

**Current UI.**
- Palette: `AppColors` with a green accent, plus a separate mobile palette `MobileColors`/`MobileTokens`.
- Theme: Material `buildAppTheme()`; mobile uses `google_fonts`, which fetches fonts at runtime.
- `AppColors.accent`: 193 uses in 46 files. Some mean "success", others mean "primary".
- Material widgets: 117 of 261 files import Material.

**Shell.** The shell is inside `app/lib/screens/main_screen.dart`: `_Sidebar` and `_TopTabBar` (1842 lines). Session tab: `app/lib/widgets/session_tab.dart`.

**Terminal theme.** "YourSSH Dark" already exists in the catalog. The new default is therefore named "YourSSH Amber" and applies to new installs only.

**State after phases 2-6.**
- The whole app (desktop and mobile) and the Snippets, DevOps and Web Tools plugins are on forui and the `yourssh_ui` components (`YsTab`, `YsFileTable`, `YsHostCard`, `YsStatusBar`, `YsPluginHost`, dialogs, toasts).
- `AppColors` and `MobileColors` stay as `@Deprecated` aliases of `YsColors`.
- `tool/check_ui_lint.sh` blocks Material `IconButton(`, `AlertDialog(`, `SnackBar(`, `Icons.`, `ScaffoldMessenger`, `showDialog(`, `showModalBottomSheet` and `TextField(`; the allowlist is empty.
- The host editor (`HostDetailPanel`) reads `existing` only in `initState`, so the shell mounts it with `hostEditorKey(editing, serial)`.
- Terminal header chips and the status bar read the host through `selectLiveHost` (fresh `HostProvider` lookup, snapshot fallback).
