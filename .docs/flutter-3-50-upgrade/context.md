# Context

**Earlier attempt.** CI was pinned to 3.47.1 in PR #113, because Flutter 3.50 rejected the Android toolchain.
- Flutter 3.50 requires Gradle ≥ 9.3.1, AGP ≥ 9.1.1 and Kotlin ≥ 2.4.10.
- The app uses Gradle 9.1.0, AGP 9.0.1 and Kotlin 2.3.20.

**Pins** (`FLUTTER_VERSION`):
- `.github/workflows/pr-test.yml`
- `.github/workflows/release.yml`, which also has two `git clone -b $FLUTTER_VERSION` steps for Windows and Linux.

**Android modules:**
- `app/android`
- `packages/flutter_pty/android` (local fork)
- any other plugin package that has an `android/` directory

**Analyzer.** About 215 analyzer infos come from material.dart deprecations in 3.47+. CI uses `--no-fatal-infos`.
