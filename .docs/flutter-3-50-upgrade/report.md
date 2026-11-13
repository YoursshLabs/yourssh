# Flutter 3.50 upgrade — report

## Versions

| | Before | After | Flutter 3.50 rejects below / warns below |
|---|---|---|---|
| Flutter | 3.47.1 | **3.50.0** (Dart 3.14.0) | — |
| Gradle | 9.1.0 | **9.5.1** | 9.3.1 / 9.5.0 |
| AGP | 9.0.1 | **9.3.3** | 9.1.1 / 9.3.1 |
| Kotlin | 2.3.20 | **2.4.21** | 2.4.10 / 2.4.20 |
| JDK | 17 | 17 | — |

`minSdk`, `targetSdk`, `compileSdk` and the NDK version are unchanged.

Each version is the newest that all parties document as compatible:
- **Kotlin 2.4.21** is the newest stable release.
- **AGP 9.3.3:** Kotlin 2.4 supports AGP up to 9.3.x.
- **Gradle 9.5.1:** AGP 9.3 needs Gradle 9.5 or later.
- **AGP 9.4 and 9.5 are excluded.** They need Gradle 9.6, which is outside the AGP range Kotlin 2.4 supports.

Sources:
- Flutter SDK 3.50.0: `DependencyVersionChecker.kt` and `gradle_utils.dart`
- kotlinlang.org, the Gradle compatibility table
- The AGP 9.3, 9.4 and 9.5 release notes

## Changes

- **CI pins.** `pr-test.yml` and `release.yml` move to 3.50.0.
- **New `android` job in pr-test.** It runs `flutter build apk --debug` with Temurin 17, has a 30-minute timeout and needs no secrets. It is part of the `test` aggregate.
- **Android build files.** `gradle-wrapper.properties` now points to Gradle 9.5.1. `settings.gradle.kts` now uses AGP 9.3.3 and Kotlin 2.4.21.
- **Lockfile.** Only the versions the 3.50 SDK forces changed:

  | Package | Version |
  |---|---|
  | clock | 1.1.3 |
  | matcher | 0.12.20 |
  | meta | 1.19.0 |
  | stack_trace | 1.12.2 |
  | test_api | 0.7.14 |
  | vector_math | 2.4.4 |
  | listen | 1.0.1 (new) |

  All URLs are on pub.dev.
- **Generated project migrations committed.** These are the `analysis_options` excludes, the macOS deployment target 12.0, and the Podfile/SPM change. The 0.3.0 release build already applied them, but develop never committed them.

## Verification

- **Analyze:** 0 errors, 0 warnings, 214 infos. The infos are `deprecated_member_use` warnings about material.dart.
- **App tests:** 2023 passed, 3 skipped.
- **Bridge tests:** rdp and vnc pass.
- **macOS build:** `flutter build macos --debug` succeeds.
- **Android:** verified only by the new CI job, since there is no Android SDK locally.

## Risks

- Only master runs the release-only builds: the release APK, the Windows and Linux desktop builds, and the macOS release build.
- `flutter analyze --suggestions` caps the AGP 9.3 template at Gradle 9.5.0. This is a tooling cap, not a build break.
- AGP 10 will remove the old DSL, including `newDsl=false`, `builtInKotlin=false` and the `BaseExtension` compileSdk hack.
- `release.yml` still uses setup-java v4, which only produces a deprecation warning.
