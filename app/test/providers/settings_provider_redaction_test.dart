import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recordingRedactionEnabled defaults true, persists via save', () async {
    SharedPreferences.setMockInitialValues({});
    final p = SettingsProvider();
    await Future<void>.delayed(Duration.zero); // let _load() finish
    expect(p.recordingRedactionEnabled, isTrue);

    await p.save(recordingRedactionEnabled: false);
    expect(p.recordingRedactionEnabled, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('recordingRedactionEnabled'), isFalse);
  });

  test('recordingRedactionEnabled loads persisted false', () async {
    SharedPreferences.setMockInitialValues(
        {'recordingRedactionEnabled': false});
    final p = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    expect(p.recordingRedactionEnabled, isFalse);
  });
}
