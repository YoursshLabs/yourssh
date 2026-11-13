import 'dart:convert';

import 'package:flutter/services.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_devops/src/models/s3_bucket_entry.dart';
import 'package:yourssh_devops/src/screens/s3_browser_screen.dart';
import 'package:yourssh_devops/src/services/s3_service.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import 'helpers/tab_to.dart';
import 'helpers/ys_test_app.dart';

class _FakeS3 extends S3Service {
  _FakeS3(this.entries, this.deleted)
    : super(
        endpoint: 'https://s3.test',
        bucket: 'b',
        accessKey: 'a',
        secretKey: 's',
      );
  final List<S3BucketEntry> entries;
  final List<String> deleted;
  final List<String> listed = [];

  @override
  Future<List<S3BucketEntry>> listObjects(String prefix) async {
    listed.add(prefix);
    return entries;
  }

  @override
  Future<void> deleteObject(String key) async => deleted.add(key);

  @override
  Future<void> putObject(
    String key,
    Uint8List data, {
    void Function(int sent, int total)? onProgress,
    String? contentType,
  }) async {}
}

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
final _store = <String, String>{};

void _mockStorage(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
    call,
  ) async {
    final args = (call.arguments as Map?) ?? {};
    final key = args['key'] as String?;
    switch (call.method) {
      case 'read':
        return _store[key];
      case 'write':
        _store[key!] = args['value'] as String;
        return null;
      case 'delete':
        _store.remove(key);
        return null;
      case 'containsKey':
        return _store.containsKey(key);
      case 'readAll':
        return Map<String, String>.from(_store);
      default:
        return null;
    }
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      null,
    ),
  );
}

void _seedConfig() {
  _store
    ..clear()
    ..['s3_configs'] = jsonEncode([
      {
        'id': '1',
        'name': 'prod',
        'endpoint': 'https://s3.example.com',
        'bucket': 'my-bucket',
        'region': 'us-east-1',
        'accessKey': 'AK',
      },
    ])
    ..['s3_secret_1'] = 'SK';
}

final _longName = '${'f' * 56}.log';
List<S3BucketEntry> _entries() => [
  const S3BucketEntry(key: 'logs/', isPrefix: true),
  S3BucketEntry(
    key: _longName,
    isPrefix: false,
    size: 2048,
    lastModified: DateTime(2026, 1, 2, 3, 4),
  ),
  const S3BucketEntry(key: 'a.txt', isPrefix: false, size: 5),
];

Future<_FakeS3> _pump(WidgetTester tester, {bool seed = true}) async {
  _mockStorage(tester);
  if (seed) {
    _seedConfig();
  } else {
    _store.clear();
  }
  final fake = _FakeS3(_entries(), []);
  await tester.pumpWidget(
    ysTestApp(S3BrowserScreen(serviceFactory: (_) => fake)),
  );
  await tester.pumpAndSettle();
  return fake;
}

Finder _row(String key) => find.byKey(ValueKey('s3-entry-$key'));

void main() {
  testWidgets('empty state offers Add Bucket', (tester) async {
    await _pump(tester, seed: false);
    expect(find.text('No buckets configured'), findsOneWidget);
    expect(find.text('Add Bucket'), findsOneWidget);
    expect(find.byTooltip('Add Bucket'), findsOneWidget);
    expect(
      FTheme.of(
        tester.element(find.text('No buckets configured')),
      ).colors.primary,
      YsColors.primary,
    );
  });

  testWidgets('add bucket dialog: secret key obscured, access key not; saved', (
    tester,
  ) async {
    await _pump(tester, seed: false);
    await tester.tap(find.widgetWithText(FButton, 'Add Bucket'));
    await tester.pumpAndSettle();
    EditableText inner(String k) => tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(ValueKey(k)),
        matching: find.byType(EditableText),
      ),
    );
    expect(inner('s3-secret-key').obscureText, isTrue);
    expect(inner('s3-access-key').obscureText, isFalse);
    expect(inner('s3-region').controller.text, 'us-east-1');
    await tester.enterText(find.byKey(const ValueKey('s3-name')), 'prod');
    await tester.enterText(
      find.byKey(const ValueKey('s3-endpoint')),
      'https://s3.example.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('s3-bucket')),
      'my-bucket',
    );
    await tester.enterText(find.byKey(const ValueKey('s3-access-key')), 'AK');
    await tester.enterText(find.byKey(const ValueKey('s3-secret-key')), 'SK');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final saved = jsonDecode(_store['s3_configs']!) as List;
    expect(saved.single['bucket'], 'my-bucket');
    expect(
      _store.entries.where((e) => e.key.startsWith('s3_secret_')).single.value,
      'SK',
    );
    expect(find.text('Edit Bucket'), findsNothing);
    expect(find.text('Empty folder'), findsNothing);
    expect(find.text('logs'), findsOneWidget);
  });

  testWidgets('lists entries; toolbar actions present with tooltips', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('logs'), findsOneWidget);
    expect(find.text(_longName), findsOneWidget);
    for (final t in [
      'Add Bucket',
      'New Folder',
      'Upload',
      'Refresh',
      'Edit Bucket',
      'Remove Bucket',
    ]) {
      expect(find.byTooltip(t), findsOneWidget, reason: t);
    }
    // Files carry the row actions; folders do not.
    for (final t in [
      'Copy URL',
      'Open',
      'Download',
      'Rename / Move',
      'Delete',
    ]) {
      expect(
        find.descendant(of: _row(_longName), matching: find.byTooltip(t)),
        findsOneWidget,
        reason: t,
      );
      expect(
        find.descendant(of: _row('logs/'), matching: find.byTooltip(t)),
        findsNothing,
        reason: t,
      );
    }
  });

  testWidgets('delete keeps the destructive confirm; Cancel is the default', (
    tester,
  ) async {
    final fake = await _pump(tester);
    await tester.tap(
      find.descendant(of: _row('a.txt'), matching: find.byTooltip('Delete')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete object'), findsOneWidget);
    expect(find.text('Delete "a.txt"?'), findsOneWidget);
    expect(
      tester.widget<FButton>(find.widgetWithText(FButton, 'Cancel')).autofocus,
      isTrue,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fake.deleted, isEmpty);
    await tester.tap(
      find.descendant(of: _row('a.txt'), matching: find.byTooltip('Delete')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(fake.deleted, ['a.txt']);
  });

  testWidgets('remove bucket keeps its confirmation wording', (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('Remove Bucket'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Bucket'), findsWidgets);
    expect(find.text('Remove "prod"?'), findsOneWidget);
    expect(
      tester.widget<FButton>(find.widgetWithText(FButton, 'Cancel')).autofocus,
      isTrue,
    );
    await tester.tap(find.widgetWithText(FButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(find.text('No buckets configured'), findsOneWidget);
  });

  testWidgets('folder row navigates in and the .. row goes up', (tester) async {
    final fake = await _pump(tester);
    await tester.tap(find.text('logs'));
    await tester.pumpAndSettle();
    expect(fake.listed.last, 'logs/');
    await tester.tap(find.text('..'));
    await tester.pumpAndSettle();
    expect(fake.listed.last, '');
  });

  testWidgets('no overflow at 900x600 with 60-char names', (tester) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Edit Bucket'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tab reaches the Add Bucket tool button', (tester) async {
    await _pump(tester);
    expect(await tabTo(tester, find.byTooltip('Add Bucket')), greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Display Name'), findsOneWidget);
  });
}
