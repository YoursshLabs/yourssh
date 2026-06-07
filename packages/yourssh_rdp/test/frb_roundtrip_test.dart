import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_rdp/src/generated/frb_generated.dart';
import 'package:yourssh_rdp/src/generated/api.dart';
import 'package:yourssh_rdp/src/native_loader.dart';

void main() {
  setUpAll(() async {
    await RustLib.init(externalLibrary: loadYoursshRdpLibrary());
  });

  test('rdpLibVersion returns crate version', () async {
    expect(await rdpLibVersion(), startsWith('yourssh_rdp 0.1.0'));
  });
}
