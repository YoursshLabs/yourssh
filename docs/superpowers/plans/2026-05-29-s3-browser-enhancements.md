# S3 Browser Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add multiple bucket configs, direct download, create folder, rename/move, and upload progress to the existing S3 browser.

**Architecture:** All changes stay in three files — a new model, the existing service, and the existing screen widget. No new providers or dependencies. Pattern matches other DevOpsHub screens (self-contained `StatefulWidget`).

**Tech Stack:** Flutter/Dart, `dart:io` (file write), `dart:convert` (JSON), `flutter_secure_storage`, `http` (StreamedRequest for progress), `file_picker`.

---

## Task 1: S3BucketConfig model

**Files:**
- Create: `app/lib/models/s3_bucket_config.dart`
- Create: `app/test/models/s3_bucket_config_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// app/test/models/s3_bucket_config_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/s3_bucket_config.dart';

void main() {
  const config = S3BucketConfig(
    id: 'abc123',
    name: 'production',
    endpoint: 'https://s3.amazonaws.com',
    bucket: 'my-bucket',
    region: 'us-east-1',
    accessKey: 'AKIA',
    secretKey: 'secret',
  );

  test('toJson excludes secretKey', () {
    final json = config.toJson();
    expect(json['id'], 'abc123');
    expect(json['name'], 'production');
    expect(json['bucket'], 'my-bucket');
    expect(json.containsKey('secretKey'), isFalse);
  });

  test('fromJson round-trips without secretKey', () {
    final json = config.toJson();
    final restored = S3BucketConfig.fromJson(json, secretKey: 'secret');
    expect(restored.id, config.id);
    expect(restored.name, config.name);
    expect(restored.endpoint, config.endpoint);
    expect(restored.bucket, config.bucket);
    expect(restored.region, config.region);
    expect(restored.accessKey, config.accessKey);
    expect(restored.secretKey, 'secret');
  });

  test('fromJson defaults region to us-east-1 when absent', () {
    final json = config.toJson()..remove('region');
    final restored = S3BucketConfig.fromJson(json, secretKey: '');
    expect(restored.region, 'us-east-1');
  });

  test('copyWith replaces only specified fields', () {
    final updated = config.copyWith(name: 'staging', secretKey: 'newsecret');
    expect(updated.id, config.id);
    expect(updated.name, 'staging');
    expect(updated.bucket, config.bucket);
    expect(updated.secretKey, 'newsecret');
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd app && flutter test test/models/s3_bucket_config_test.dart
```

Expected: compilation error — `s3_bucket_config.dart` does not exist yet.

- [ ] **Step 3: Create the model**

```dart
// app/lib/models/s3_bucket_config.dart
class S3BucketConfig {
  final String id;
  final String name;
  final String endpoint;
  final String bucket;
  final String region;
  final String accessKey;
  final String secretKey;

  const S3BucketConfig({
    required this.id,
    required this.name,
    required this.endpoint,
    required this.bucket,
    required this.region,
    required this.accessKey,
    required this.secretKey,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'endpoint': endpoint,
    'bucket': bucket,
    'region': region,
    'accessKey': accessKey,
  };

  factory S3BucketConfig.fromJson(
    Map<String, dynamic> json, {
    required String secretKey,
  }) =>
      S3BucketConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        endpoint: json['endpoint'] as String,
        bucket: json['bucket'] as String,
        region: (json['region'] as String?) ?? 'us-east-1',
        accessKey: json['accessKey'] as String,
        secretKey: secretKey,
      );

  S3BucketConfig copyWith({
    String? name,
    String? endpoint,
    String? bucket,
    String? region,
    String? accessKey,
    String? secretKey,
  }) =>
      S3BucketConfig(
        id: id,
        name: name ?? this.name,
        endpoint: endpoint ?? this.endpoint,
        bucket: bucket ?? this.bucket,
        region: region ?? this.region,
        accessKey: accessKey ?? this.accessKey,
        secretKey: secretKey ?? this.secretKey,
      );
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
cd app && flutter test test/models/s3_bucket_config_test.dart
```

Expected: `All tests passed.`

- [ ] **Step 5: Commit**

```bash
git add app/lib/models/s3_bucket_config.dart app/test/models/s3_bucket_config_test.dart
git commit -m "feat: add S3BucketConfig model with JSON serialization"
```

---

## Task 2: S3Service — copyObject, downloadObject, putObject with progress

**Files:**
- Modify: `app/lib/services/s3_service.dart`

The current `putObject` signature is:
```dart
Future<void> putObject(String key, Uint8List data, {String contentType = 'application/octet-stream'})
```

- [ ] **Step 1: Add `copyObject` method**

Insert after the `deleteObject` method (after line 159):

```dart
  /// Copy object from [sourceKey] to [destKey] within the same bucket.
  Future<void> copyObject(String sourceKey, String destKey) async {
    final uri = _buildUri(path: '/$bucket/$destKey');
    final now = DateTime.now().toUtc();
    final dateStamp = _dateStamp(now);
    final amzDate = _amzDate(now);
    final bodyHash = sha256.convert(<int>[]).toString();
    final host = _host;
    final encodedSource = Uri.encodeComponent('/$bucket/$sourceKey');

    final headers = {
      'host': host,
      'x-amz-content-sha256': bodyHash,
      'x-amz-copy-source': encodedSource,
      'x-amz-date': amzDate,
      'x-amz-metadata-directive': 'COPY',
    };

    final canonicalRequest =
        _canonicalRequest('PUT', '/$bucket/$destKey', '', headers, bodyHash);
    final authHeader = _authHeader(canonicalRequest, headers, dateStamp, amzDate);
    headers['Authorization'] = authHeader;

    final response = await http.put(uri, headers: headers);
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('S3 copy failed: ${response.statusCode} ${response.body}');
    }
  }
```

- [ ] **Step 2: Add `downloadObject` method**

Insert after `copyObject`:

```dart
  /// Download object at [key] and return its bytes.
  Future<Uint8List> downloadObject(String key) async {
    final uri = _buildUri(path: '/$bucket/$key');
    final response = await _signedGet(uri);
    if (response.statusCode != 200) {
      throw Exception('S3 download failed: ${response.statusCode} ${response.body}');
    }
    return response.bodyBytes;
  }
```

- [ ] **Step 3: Replace `putObject` with progress-capable version**

Replace the entire `putObject` method (lines 111–134 in the original) with:

```dart
  /// Upload [data] to [key]. Optional [onProgress] receives (bytesSent, totalBytes).
  Future<void> putObject(
    String key,
    Uint8List data, {
    String contentType = 'application/octet-stream',
    void Function(int sent, int total)? onProgress,
  }) async {
    final uri = _buildUri(path: '/$bucket/$key');
    final now = DateTime.now().toUtc();
    final dateStamp = _dateStamp(now);
    final amzDate = _amzDate(now);
    final bodyHash = sha256.convert(data).toString();
    final host = _host;

    final headers = {
      'content-type': contentType,
      'host': host,
      'x-amz-content-sha256': bodyHash,
      'x-amz-date': amzDate,
    };

    final canonicalRequest =
        _canonicalRequest('PUT', '/$bucket/$key', '', headers, bodyHash);
    final authHeader = _authHeader(canonicalRequest, headers, dateStamp, amzDate);
    headers['Authorization'] = authHeader;

    if (onProgress == null) {
      final response = await http.put(uri, headers: headers, body: data);
      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('S3 upload failed: ${response.statusCode} ${response.body}');
      }
      return;
    }

    final client = http.Client();
    try {
      final request = http.StreamedRequest('PUT', uri);
      headers.forEach((k, v) => request.headers[k] = v);
      request.contentLength = data.length;

      final responseFuture = client.send(request);
      const chunkSize = 65536;
      var sent = 0;
      for (var i = 0; i < data.length; i += chunkSize) {
        final end = (i + chunkSize).clamp(0, data.length);
        request.sink.add(data.sublist(i, end));
        sent = end;
        onProgress(sent, data.length);
      }
      await request.sink.close();

      final streamed = await responseFuture;
      if (streamed.statusCode != 200 && streamed.statusCode != 204) {
        final body = await streamed.stream.bytesToString();
        throw Exception('S3 upload failed: ${streamed.statusCode} $body');
      }
    } finally {
      client.close();
    }
  }
```

- [ ] **Step 4: Verify the app compiles**

```bash
cd app && flutter analyze lib/services/s3_service.dart
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add app/lib/services/s3_service.dart
git commit -m "feat: add S3Service copyObject, downloadObject, putObject progress"
```

---

## Task 3: S3BrowserScreen — multi-bucket state refactor

**Files:**
- Modify: `app/lib/widgets/s3_browser_screen.dart`

This task replaces the single-config state (5 `TextEditingController`s, `_configured` flag) with a multi-config list, dropdown switcher, and migration logic. After this task all _existing_ features (browse, upload, delete, copy URL, open) continue to work plus bucket switching is live.

- [ ] **Step 1: Update imports at top of file**

Replace the existing import block with:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/s3_bucket_config.dart';
import '../models/s3_bucket_entry.dart';
import '../services/s3_service.dart';
import '../theme/app_theme.dart';
```

- [ ] **Step 2: Replace `_S3BrowserScreenState` state fields**

Replace everything from `static const _storage = FlutterSecureStorage();` through the closing of the field declarations block (ends before `@override void initState`) with:

```dart
  static const _storage = FlutterSecureStorage();

  List<S3BucketConfig> _configs = [];
  int _activeIndex = -1;
  S3Service? _service;
  bool _loading = false;
  String? _error;
  String _prefix = '';
  final List<String> _breadcrumbs = [];
  List<S3BucketEntry> _entries = [];
  double? _uploadProgress;
```

- [ ] **Step 3: Replace `initState`, `dispose`, and old config methods**

Replace `initState`, `dispose`, `_loadConfig`, `_saveConfig`, `_connect`, `_connectWithCurrentConfig` with:

```dart
  @override
  void initState() {
    super.initState();
    _loadConfigs();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadConfigs() async {
    final oldEndpoint = await _storage.read(key: 's3_endpoint');
    if (oldEndpoint != null) {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final bucket = await _storage.read(key: 's3_bucket') ?? '';
      final config = S3BucketConfig(
        id: id,
        name: bucket.isEmpty ? 'default' : bucket,
        endpoint: oldEndpoint,
        bucket: bucket,
        region: await _storage.read(key: 's3_region') ?? 'us-east-1',
        accessKey: await _storage.read(key: 's3_access_key') ?? '',
        secretKey: await _storage.read(key: 's3_secret_key') ?? '',
      );
      await _saveConfigs([config]);
      for (final k in ['s3_endpoint', 's3_bucket', 's3_region', 's3_access_key', 's3_secret_key']) {
        await _storage.delete(key: k);
      }
      if (!mounted) return;
      setState(() { _configs = [config]; _activeIndex = 0; });
      _activateConfig(0);
      return;
    }

    final raw = await _storage.read(key: 's3_configs');
    if (raw == null) {
      if (mounted) setState(() {});
      return;
    }
    final jsonList = jsonDecode(raw) as List<dynamic>;
    final configs = <S3BucketConfig>[];
    for (final item in jsonList) {
      final id = (item as Map<String, dynamic>)['id'] as String;
      final secret = await _storage.read(key: 's3_secret_$id') ?? '';
      configs.add(S3BucketConfig.fromJson(item, secretKey: secret));
    }
    if (!mounted) return;
    setState(() {
      _configs = configs;
      _activeIndex = configs.isNotEmpty ? 0 : -1;
    });
    if (configs.isNotEmpty) _activateConfig(0);
  }

  Future<void> _saveConfigs(List<S3BucketConfig> configs) async {
    await _storage.write(
      key: 's3_configs',
      value: jsonEncode(configs.map((c) => c.toJson()).toList()),
    );
    for (final c in configs) {
      await _storage.write(key: 's3_secret_${c.id}', value: c.secretKey);
    }
  }

  void _activateConfig(int index) {
    if (index < 0 || index >= _configs.length) return;
    final c = _configs[index];
    _service = S3Service(
      endpoint: c.endpoint,
      bucket: c.bucket,
      accessKey: c.accessKey,
      secretKey: c.secretKey,
      region: c.region,
    );
    setState(() {
      _activeIndex = index;
      _prefix = '';
      _breadcrumbs.clear();
      _entries = [];
      _error = null;
    });
    _listObjects();
  }

  Future<void> _showConfigDialog({S3BucketConfig? existing, int? editIndex}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final endpointCtrl = TextEditingController(text: existing?.endpoint ?? '');
    final bucketCtrl = TextEditingController(text: existing?.bucket ?? '');
    final regionCtrl = TextEditingController(text: existing?.region ?? 'us-east-1');
    final accessCtrl = TextEditingController(text: existing?.accessKey ?? '');
    final secretCtrl = TextEditingController(text: existing?.secretKey ?? '');
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.sidebar,
          title: Text(
            existing == null ? 'Add Bucket' : 'Edit Bucket',
            style: const TextStyle(color: AppColors.textPrimary),
          ),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field(nameCtrl, 'Display Name', 'production'),
                  _field(endpointCtrl, 'Endpoint', 'https://s3.amazonaws.com'),
                  _field(bucketCtrl, 'Bucket', 'my-bucket'),
                  _field(regionCtrl, 'Region', 'us-east-1'),
                  _field(accessCtrl, 'Access Key', 'AKIAIOSFODNN7EXAMPLE'),
                  _field(secretCtrl, 'Secret Key', '••••', obscure: true),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final id = existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
      final displayName = nameCtrl.text.trim();
      final config = S3BucketConfig(
        id: id,
        name: displayName.isEmpty ? bucketCtrl.text.trim() : displayName,
        endpoint: endpointCtrl.text.trim(),
        bucket: bucketCtrl.text.trim(),
        region: regionCtrl.text.trim(),
        accessKey: accessCtrl.text.trim(),
        secretKey: secretCtrl.text.trim(),
      );
      final newConfigs = List<S3BucketConfig>.from(_configs);
      final newActive = editIndex ?? newConfigs.length;
      if (editIndex != null) {
        newConfigs[editIndex] = config;
      } else {
        newConfigs.add(config);
      }
      await _saveConfigs(newConfigs);
      setState(() => _configs = newConfigs);
      _activateConfig(newActive);
    } finally {
      nameCtrl.dispose(); endpointCtrl.dispose(); bucketCtrl.dispose();
      regionCtrl.dispose(); accessCtrl.dispose(); secretCtrl.dispose();
    }
  }

  Future<void> _deleteConfig(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('Remove Bucket', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Remove "${_configs[index].name}"?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _storage.delete(key: 's3_secret_${_configs[index].id}');
    final newConfigs = List<S3BucketConfig>.from(_configs)..removeAt(index);
    await _saveConfigs(newConfigs);
    if (newConfigs.isEmpty) {
      setState(() {
        _configs = newConfigs;
        _activeIndex = -1;
        _service = null;
        _entries = [];
        _prefix = '';
        _breadcrumbs.clear();
      });
    } else {
      setState(() => _configs = newConfigs);
      _activateConfig(newConfigs.length > index ? index : index - 1);
    }
  }

  Future<void> _createFolder() async {}
```

- [ ] **Step 4: Replace `build()`, replace `_buildToolbar()`, add `_buildBucketSelector()` and `_buildEmptyState()` (new)**

Replace the existing `build()` method with:

```dart
  @override
  Widget build(BuildContext context) {
    final hasConfig = _configs.isNotEmpty && _activeIndex >= 0;
    return Column(
      children: [
        _buildToolbar(),
        Container(height: 1, color: AppColors.border),
        if (!hasConfig)
          Expanded(child: _buildEmptyState())
        else ...[
          _buildBreadcrumbs(),
          Container(height: 1, color: AppColors.border),
          if (_uploadProgress != null)
            LinearProgressIndicator(value: _uploadProgress, minHeight: 2),
          Expanded(child: _buildFileList()),
        ],
      ],
    );
  }
```

Replace the existing `_buildToolbar()` method with (and add the two new methods `_buildBucketSelector` and `_buildEmptyState` immediately after it):

```dart
  Widget _buildToolbar() {
    final hasConfig = _configs.isNotEmpty && _activeIndex >= 0;
    return Container(
      height: 44,
      color: AppColors.sidebar,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.cloud_outlined, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          if (hasConfig)
            _buildBucketSelector()
          else
            const Text(
              'S3 Browser',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          const Spacer(),
          _toolBtn(Icons.add, 'Add Bucket', () => _showConfigDialog()),
          if (hasConfig) ...[
            const SizedBox(width: 4),
            _toolBtn(Icons.create_new_folder_outlined, 'New Folder', _createFolder),
            const SizedBox(width: 4),
            _toolBtn(Icons.upload_outlined, 'Upload', _upload),
            const SizedBox(width: 4),
            _toolBtn(Icons.refresh, 'Refresh', _listObjects),
          ],
        ],
      ),
    );
  }

  Widget _buildBucketSelector() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButton<int>(
          value: _activeIndex,
          underline: const SizedBox(),
          dropdownColor: AppColors.card,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          items: _configs.asMap().entries.map((e) => DropdownMenuItem<int>(
            value: e.key,
            child: Text('s3://${e.value.bucket}'),
          )).toList(),
          onChanged: (index) {
            if (index != null && index != _activeIndex) _activateConfig(index);
          },
        ),
        _toolBtn(
          Icons.edit_outlined,
          'Edit Bucket',
          () => _showConfigDialog(existing: _configs[_activeIndex], editIndex: _activeIndex),
        ),
        _toolBtn(
          Icons.delete_outlined,
          'Remove Bucket',
          () => _deleteConfig(_activeIndex),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_outlined, color: AppColors.textTertiary, size: 48),
          const SizedBox(height: 12),
          const Text(
            'No buckets configured',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Bucket'),
            onPressed: () => _showConfigDialog(),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 5: Remove `_buildConfigForm()` method**

Delete the entire `_buildConfigForm()` method (the one with `SingleChildScrollView`, endpoint/bucket/region/access/secret fields, and the "Connect" `FilledButton`).

- [ ] **Step 6: Verify compile + analyze**

```bash
cd app && flutter analyze lib/widgets/s3_browser_screen.dart
```

Expected: no errors (warnings about unused imports are fine if any).

- [ ] **Step 7: Commit**

```bash
git add app/lib/widgets/s3_browser_screen.dart
git commit -m "feat: multi-bucket config — dropdown switcher, add/edit/delete buckets, migration"
```

---

## Task 4: Upload progress

**Files:**
- Modify: `app/lib/widgets/s3_browser_screen.dart`

- [ ] **Step 1: Replace `_upload()` method**

Replace the existing `_upload()` method with:

```dart
  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    final key = _prefix + file.name;
    if (mounted) setState(() => _error = null);
    try {
      await _service!.putObject(
        key,
        file.bytes!,
        onProgress: (sent, total) {
          if (mounted) setState(() => _uploadProgress = sent / total);
        },
      );
      if (mounted) setState(() => _uploadProgress = null);
      await _listObjects();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Uploaded ${file.name}')),
        );
      }
    } catch (e) {
      if (mounted) setState(() { _uploadProgress = null; _error = e.toString(); });
    }
  }
```

- [ ] **Step 2: Verify `_uploadProgress` and `LinearProgressIndicator` are wired**

Confirm that in the `build()` method added in Task 3 there is:
```dart
if (_uploadProgress != null)
  LinearProgressIndicator(value: _uploadProgress, minHeight: 2),
```
This was added in Task 3 — no additional code change needed here.

- [ ] **Step 3: Verify compile**

```bash
cd app && flutter analyze lib/widgets/s3_browser_screen.dart
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add app/lib/widgets/s3_browser_screen.dart
git commit -m "feat: upload progress bar for S3 file upload"
```

---

## Task 5: Direct download

**Files:**
- Modify: `app/lib/widgets/s3_browser_screen.dart`

- [ ] **Step 1: Add `_download` and `_getDownloadsPath` methods**

Add after `_openInBrowser`:

```dart
  Future<void> _download(S3BucketEntry entry) async {
    setState(() => _loading = true);
    try {
      final bytes = await _service!.downloadObject(entry.key);
      final path = '${_getDownloadsPath()}/${entry.name}';
      await File(path).writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to Downloads/${entry.name}')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _getDownloadsPath() {
    if (Platform.isWindows) {
      return '${Platform.environment['USERPROFILE']}\\Downloads';
    }
    return '${Platform.environment['HOME']}/Downloads';
  }
```

- [ ] **Step 2: Add `onDownload` callback to `_EntryTile`**

In the `_EntryTile` StatefulWidget class, add one field:

```dart
  final VoidCallback? onDownload;
```

Update the constructor to include it:

```dart
  const _EntryTile({
    required this.entry,
    this.onNavigate,
    this.onDelete,
    this.onCopyUrl,
    this.onOpenUrl,
    this.onDownload,
  });
```

In `_EntryTileState.build()`, inside the trailing `Row` (after the `onOpenUrl` button), add:

```dart
                    if (widget.onDownload != null)
                      _actionBtn(Icons.download_outlined, 'Download', widget.onDownload!),
```

- [ ] **Step 3: Wire `onDownload` in `_buildFileList`**

In `_buildFileList()`, find the `_EntryTile(...)` constructor call and add:

```dart
          onDownload: entry.isPrefix ? null : () => _download(entry),
```

- [ ] **Step 4: Verify compile**

```bash
cd app && flutter analyze lib/widgets/s3_browser_screen.dart
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add app/lib/widgets/s3_browser_screen.dart
git commit -m "feat: download S3 object directly to Downloads folder"
```

---

## Task 6: Create folder

**Files:**
- Modify: `app/lib/widgets/s3_browser_screen.dart`

- [ ] **Step 1: Replace the `_createFolder()` stub with the real implementation**

Replace `Future<void> _createFolder() async {}` with:

```dart
  Future<void> _createFolder() async {
    final ctrl = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.sidebar,
          title: const Text('New Folder', style: TextStyle(color: AppColors.textPrimary)),
          content: _field(ctrl, 'Folder Name', 'images'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final name = ctrl.text.trim();
      if (name.isEmpty || name.contains('/')) {
        setState(() => _error = 'Folder name must not be empty or contain "/"');
        return;
      }
      setState(() => _loading = true);
      try {
        await _service!.putObject('$_prefix$name/', Uint8List(0));
        await _listObjects();
      } catch (e) {
        if (mounted) setState(() => _error = e.toString());
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    } finally {
      ctrl.dispose();
    }
  }
```

- [ ] **Step 2: Verify compile**

```bash
cd app && flutter analyze lib/widgets/s3_browser_screen.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add app/lib/widgets/s3_browser_screen.dart
git commit -m "feat: create folder in S3 bucket"
```

---

## Task 7: Rename / Move

**Files:**
- Modify: `app/lib/widgets/s3_browser_screen.dart`

- [ ] **Step 1: Add `_renameMove` method**

Add after `_createFolder`:

```dart
  Future<void> _renameMove(S3BucketEntry entry) async {
    final currentFolder = entry.key.substring(0, entry.key.length - entry.name.length);
    final folderCtrl = TextEditingController(text: currentFolder);
    final nameCtrl = TextEditingController(text: entry.name);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppColors.sidebar,
          title: const Text('Rename / Move', style: TextStyle(color: AppColors.textPrimary)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(folderCtrl, 'Folder Path', 'images/2024/'),
                _field(nameCtrl, 'File Name', 'photo.jpg'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Move'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final destKey = folderCtrl.text + nameCtrl.text.trim();
      if (destKey == entry.key) return;

      setState(() => _loading = true);
      try {
        await _service!.copyObject(entry.key, destKey);
        await _service!.deleteObject(entry.key);
        await _listObjects();
      } catch (e) {
        if (mounted) setState(() => _error = e.toString());
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    } finally {
      folderCtrl.dispose();
      nameCtrl.dispose();
    }
  }
```

- [ ] **Step 2: Add `onRenameMove` callback to `_EntryTile`**

In the `_EntryTile` StatefulWidget class, add:

```dart
  final VoidCallback? onRenameMove;
```

Update constructor:

```dart
  const _EntryTile({
    required this.entry,
    this.onNavigate,
    this.onDelete,
    this.onCopyUrl,
    this.onOpenUrl,
    this.onDownload,
    this.onRenameMove,
  });
```

In `_EntryTileState.build()`, inside the trailing `Row` (add before the delete button so order is: Copy URL, Open, Download, Rename/Move, Delete):

```dart
                    if (widget.onRenameMove != null)
                      _actionBtn(Icons.drive_file_rename_outline, 'Rename / Move', widget.onRenameMove!),
```

- [ ] **Step 3: Wire `onRenameMove` in `_buildFileList`**

In `_buildFileList()`, in the `_EntryTile(...)` constructor call add:

```dart
          onRenameMove: entry.isPrefix ? null : () => _renameMove(entry),
```

- [ ] **Step 4: Verify compile**

```bash
cd app && flutter analyze lib/widgets/s3_browser_screen.dart
```

Expected: no errors.

- [ ] **Step 5: Run all tests**

```bash
cd app && flutter test
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add app/lib/widgets/s3_browser_screen.dart
git commit -m "feat: rename and move S3 objects via copy+delete"
```

---

## Final verification

- [ ] **Run full analyze**

```bash
cd app && flutter analyze
```

Expected: no errors.

- [ ] **Run all tests**

```bash
cd app && flutter test
```

Expected: all tests pass including `test/models/s3_bucket_config_test.dart`.
