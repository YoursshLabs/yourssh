import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/app_release.dart';
import 'package:yourssh/providers/update_provider.dart';
import 'package:yourssh/services/update_service.dart';

/// Counts fetches and returns a scripted release.
class _FakeService extends UpdateService {
  _FakeService(this._release);
  final AppRelease _release;
  int fetchCount = 0;
  @override
  Future<AppRelease> fetchLatestRelease() async {
    fetchCount++;
    return _release;
  }
}

AppRelease _rel(String tag) =>
    AppRelease.fromJson({'tag_name': tag, 'assets': []});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('manual check finds a newer version -> available', () async {
    final svc = _FakeService(_rel('v0.2.0'));
    final p = UpdateProvider(svc, currentVersion: '0.1.18');
    await p.checkForUpdates(manual: true);
    expect(p.status, UpdateStatus.available);
    expect(p.latestRelease!.version, '0.2.0');
    expect(svc.fetchCount, 1);
  });

  test('same version -> upToDate', () async {
    final svc = _FakeService(_rel('v0.1.18'));
    final p = UpdateProvider(svc, currentVersion: '0.1.18');
    await p.checkForUpdates(manual: true);
    expect(p.status, UpdateStatus.upToDate);
  });

  test('auto check is skipped within 24h of the last check', () async {
    final now = DateTime.utc(2026, 6, 3, 12);
    SharedPreferences.setMockInitialValues({
      'last_update_check': now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
    });
    final svc = _FakeService(_rel('v0.2.0'));
    final p = UpdateProvider(svc, currentVersion: '0.1.18', now: () => now);
    await p.checkForUpdates(); // auto
    expect(svc.fetchCount, 0);
    expect(p.status, UpdateStatus.idle);
  });

  test('auto check runs when >24h since last check', () async {
    final now = DateTime.utc(2026, 6, 3, 12);
    SharedPreferences.setMockInitialValues({
      'last_update_check': now.subtract(const Duration(hours: 25)).millisecondsSinceEpoch,
    });
    final svc = _FakeService(_rel('v0.2.0'));
    final p = UpdateProvider(svc, currentVersion: '0.1.18', now: () => now);
    await p.checkForUpdates(); // auto
    expect(svc.fetchCount, 1);
    expect(p.status, UpdateStatus.available);
  });

  test('dismiss hides the banner for that version only', () async {
    final svc = _FakeService(_rel('v0.2.0'));
    final p = UpdateProvider(svc, currentVersion: '0.1.18');
    await p.checkForUpdates(manual: true);
    expect(p.showBanner, isTrue);
    p.dismiss();
    expect(p.showBanner, isFalse);
  });
}
