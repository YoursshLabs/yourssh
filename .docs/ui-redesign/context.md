# Context

**Spike.** forui 0.27.7 needs Flutter ≥3.47 and Dart ≥3.13. CI pins Flutter 3.47.1. The throwaway spike lives in the session scratchpad.

**Current UI.**
- Palette: `AppColors` with a green accent, plus a separate mobile palette `MobileColors`/`MobileTokens`.
- Theme: Material `buildAppTheme()`; mobile uses `google_fonts`, which fetches fonts at runtime.
- `AppColors.accent`: 193 uses in 46 files. Some mean "success", others mean "primary".
- Material widgets: 117 of 261 files import Material.

**Shell.** The shell is inside `app/lib/screens/main_screen.dart`: `_Sidebar` and `_TopTabBar` (1842 lines). Session tab: `app/lib/widgets/session_tab.dart`.

**Terminal theme.** "YourSSH Dark" already exists in the catalog. The new default is therefore named "YourSSH Amber" and applies to new installs only.
