# Plan

1. Bump `FLUTTER_VERSION` to 3.50.0 in every workflow.
2. Bump Android Gradle, AGP and Kotlin to Flutter 3.50's minimums or later, in app and in the forked plugin modules. Migrate any AGP 9 DSL breakages.
3. Run `flutter pub get` on 3.50. The lock must contain only pub.dev URLs.
4. Run `flutter analyze` (0 errors) and `flutter test` (green). Build macOS and Android (`flutter build apk --debug`) locally.
5. Open a PR and get CI green.
