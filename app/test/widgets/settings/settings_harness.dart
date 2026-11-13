import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yourssh/models/app_release.dart';
import 'package:yourssh/providers/ai_chat_provider.dart';
import 'package:yourssh/providers/audit_provider.dart';
import 'package:yourssh/providers/settings_provider.dart';
import 'package:yourssh/providers/sync_provider.dart';
import 'package:yourssh/providers/update_provider.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/update_service.dart';

import '../../helpers/ys_test_app.dart';

/// Scripted release source; counts fetches.
class FakeUpdateService extends UpdateService {
  FakeUpdateService([AppRelease? release])
    : release =
          release ?? AppRelease.fromJson({'tag_name': 'v0.1.34', 'assets': []});
  AppRelease release;
  int fetches = 0;

  @override
  Future<AppRelease> fetchLatestRelease() async {
    fetches++;
    return release;
  }
}

const _secureChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// In-memory stand-in for the secure-storage plugin. [failWrites] makes
/// every write throw (the Keychain refusing), so secrets fall back to prefs.
class FakeSecureStore {
  final Map<String, String> values = {};
  bool failWrites = false;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureChannel, (call) async {
          final args = (call.arguments as Map?) ?? const {};
          final key = args['key'] as String?;
          switch (call.method) {
            case 'write':
              if (failWrites) throw PlatformException(code: '-34018');
              final value = args['value'] as String?;
              if (key != null && value != null) values[key] = value;
              return null;
            case 'read':
              return values[key];
            case 'delete':
              values.remove(key);
              return null;
            case 'readAll':
              return Map<String, String>.from(values);
            case 'containsKey':
              return values.containsKey(key);
            default:
              return null;
          }
        });
  }

  void uninstall() => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(_secureChannel, null);
}

/// The providers the Settings screen reads, built fresh per test.
class SettingsHarness {
  SettingsHarness({AppRelease? release, this.audit})
    : storage = StorageService(),
      update = FakeUpdateService(release) {
    settings = SettingsProvider();
    sync = SyncProvider(storage: storage);
    updates = UpdateProvider(update, currentVersion: '0.1.34');
    ai = AiChatProvider();
  }

  final StorageService storage;
  final FakeUpdateService update;
  final AuditProvider? audit;
  late final SettingsProvider settings;
  late final SyncProvider sync;
  late final UpdateProvider updates;
  late final AiChatProvider ai;

  Widget wrap(Widget child) => MultiProvider(
    providers: [
      Provider<StorageService>.value(value: storage),
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ChangeNotifierProvider<SyncProvider>.value(value: sync),
      ChangeNotifierProvider<UpdateProvider>.value(value: updates),
      ChangeNotifierProvider<AiChatProvider>.value(value: ai),
      if (audit != null)
        ChangeNotifierProvider<AuditProvider>.value(value: audit!),
    ],
    child: ysTestApp(child),
  );

  /// Pumps [child] (a section, or the whole screen) at [size] and lets the
  /// providers finish loading prefs / secure storage.
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(1000, 2400),
    bool scroll = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      wrap(scroll ? SingleChildScrollView(child: child) : child),
    );
    await tester.pumpAndSettle();
  }
}

/// Prefs a test starts from.
void mockPrefs([Map<String, Object> values = const {}]) =>
    SharedPreferences.setMockInitialValues(values);

/// True when the primary focus sits on the widget with [key] or inside it.
bool hasFocusWithin(WidgetTester tester, Key key) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  final target = tester.element(find.byKey(key));
  if (ctx == target) return true;
  var found = false;
  ctx.visitAncestorElements((e) {
    if (e == target) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// The [EditableText] inside the field with [key].
EditableText editableIn(WidgetTester tester, Key key) =>
    tester.widget<EditableText>(
      find.descendant(of: find.byKey(key), matching: find.byType(EditableText)),
    );

/// Opens the select with [key] and picks the option labelled [option].
Future<void> pickOption(WidgetTester tester, Key key, String option) async {
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

/// Taps the switch control of the [FSwitch] with [key] (its label only
/// reacts where there is text).
Future<void> tapSwitch(WidgetTester tester, Key key) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(key),
      // forui renders cupertino_ui's CupertinoSwitch, not Flutter's.
      matching: find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'CupertinoSwitch',
      ),
    ),
  );
  await tester.pumpAndSettle();
}
