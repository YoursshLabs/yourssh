// Driver for on-device integration tests that capture screenshots.
//
// `flutter test integration_test/...` runs the test on the device but uninstalls
// the app afterwards, taking anything the test wrote inside the app's own
// directories with it. Screenshots therefore travel back over the driver
// connection instead, and this file is what writes them on the host:
//
//   cd app && flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/mobile_screenshots_test.dart \
//     -d emulator-5554
//
// Screenshot names are treated as paths relative to the repo root, so a test
// calling takeScreenshot('screenshots/11-mobile/01-hosts-list') lands there.
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = File('../$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      stdout.writeln('WROTE: ${file.path}');
      return true;
    },
  );
}
