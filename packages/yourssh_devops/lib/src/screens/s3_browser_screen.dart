import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
// Tooltip is Material plumbing; the rest of the screen is forui.
// Migrating the app to material_ui is a separate later step.
// ignore: deprecated_member_use
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../models/s3_bucket_config.dart';
import '../models/s3_bucket_entry.dart';
import '../services/s3_service.dart';

class S3BrowserScreen extends StatefulWidget {
  /// [serviceFactory] lets tests supply a fake [S3Service] so no request
  /// leaves the process; the app uses the default.
  const S3BrowserScreen({super.key, this.serviceFactory});

  final S3Service Function(S3BucketConfig config)? serviceFactory;

  @override
  State<S3BrowserScreen> createState() => _S3BrowserScreenState();
}

class _S3BrowserScreenState extends State<S3BrowserScreen> {
  // Mirrors the app's StorageService.macOsKeychainOptions: the default
  // data-protection Keychain fails with -34018 on ad-hoc-signed macOS builds.
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(
      accountName: 'yourssh',
      useDataProtectionKeyChain: false,
    ),
  );

  List<S3BucketConfig> _configs = [];
  int _activeIndex = -1;
  S3Service? _service;
  bool _loading = false;
  String? _error;
  String _prefix = '';
  final List<String> _breadcrumbs = [];
  List<S3BucketEntry> _entries = [];
  double? _uploadProgress;

  @override
  void initState() {
    super.initState();
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    try {
      await _loadConfigsUnsafe();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'Could not read saved S3 configs from secure storage: $e',
        );
      }
    }
  }

  Future<void> _loadConfigsUnsafe() async {
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
      // Keep the legacy keys if the new copy could not be stored.
      if (await _saveConfigs([config])) {
        for (final k in [
          's3_endpoint',
          's3_bucket',
          's3_region',
          's3_access_key',
          's3_secret_key',
        ]) {
          await _storage.delete(key: k);
        }
      }
      if (!mounted) return;
      setState(() {
        _configs = [config];
        _activeIndex = 0;
      });
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

  /// Persists the configs; on failure shows an error and returns false
  /// instead of throwing.
  Future<bool> _saveConfigs(List<S3BucketConfig> configs) async {
    try {
      await _storage.write(
        key: 's3_configs',
        value: jsonEncode(configs.map((c) => c.toJson()).toList()),
      );
      for (final c in configs) {
        await _storage.write(key: 's3_secret_${c.id}', value: c.secretKey);
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Could not save S3 configs to secure storage: $e',
        );
      }
      return false;
    }
  }

  void _activateConfig(int index) {
    if (index < 0 || index >= _configs.length) return;
    final c = _configs[index];
    _service =
        widget.serviceFactory?.call(c) ??
        S3Service(
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

  Future<void> _showConfigDialog({
    S3BucketConfig? existing,
    int? editIndex,
  }) async {
    final values = await showYsDialog<List<String>>(
      context,
      builder: (_) => _FieldsDialog(
        title: existing == null ? 'Add Bucket' : 'Edit Bucket',
        confirmLabel: 'Save',
        fields: [
          _FieldSpec(
            's3-name',
            'Display Name',
            'production',
            existing?.name ?? '',
          ),
          _FieldSpec(
            's3-endpoint',
            'Endpoint',
            'https://s3.amazonaws.com',
            existing?.endpoint ?? '',
          ),
          _FieldSpec(
            's3-bucket',
            'Bucket',
            'my-bucket',
            existing?.bucket ?? '',
          ),
          _FieldSpec(
            's3-region',
            'Region',
            'us-east-1',
            existing?.region ?? 'us-east-1',
          ),
          _FieldSpec(
            's3-access-key',
            'Access Key',
            'AKIAIOSFODNN7EXAMPLE',
            existing?.accessKey ?? '',
          ),
          _FieldSpec(
            's3-secret-key',
            'Secret Key',
            '••••',
            existing?.secretKey ?? '',
            obscure: true,
          ),
        ],
      ),
    );
    if (values == null || !mounted) return;
    final [
      nameText,
      endpointText,
      bucketText,
      regionText,
      accessText,
      secretText,
    ] = values;
    final id = existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final displayName = nameText.trim();
    final config = S3BucketConfig(
      id: id,
      name: displayName.isEmpty ? bucketText.trim() : displayName,
      endpoint: endpointText.trim(),
      bucket: bucketText.trim(),
      region: regionText.trim(),
      accessKey: accessText.trim(),
      secretKey: secretText.trim(),
    );
    final newConfigs = List<S3BucketConfig>.from(_configs);
    final newActive = editIndex ?? newConfigs.length;
    if (editIndex != null) {
      newConfigs[editIndex] = config;
    } else {
      newConfigs.add(config);
    }
    final saved = await _saveConfigs(newConfigs);
    if (!mounted) return;
    final saveError = _error;
    setState(() => _configs = newConfigs);
    _activateConfig(newActive);
    // _activateConfig clears _error; keep the save failure visible.
    if (!saved && mounted) setState(() => _error = saveError);
  }

  Future<void> _deleteConfig(int index) async {
    final confirmed = await showYsConfirm(
      context,
      title: 'Remove Bucket',
      message: 'Remove "${_configs[index].name}"?',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await _storage.delete(key: 's3_secret_${_configs[index].id}');
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              _error = 'Could not remove the S3 secret from secure storage: $e',
        );
      }
    }
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

  Future<void> _createFolder() async {
    final values = await showYsDialog<List<String>>(
      context,
      builder: (_) => const _FieldsDialog(
        title: 'New Folder',
        confirmLabel: 'Create',
        fields: [_FieldSpec('s3-folder-name', 'Folder Name', 'images', '')],
      ),
    );
    if (values == null || !mounted) return;
    final name = values[0].trim();
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
  }

  Future<void> _renameMove(S3BucketEntry entry) async {
    final currentFolder = entry.key.substring(
      0,
      entry.key.length - entry.name.length,
    );
    final values = await showYsDialog<List<String>>(
      context,
      builder: (_) => _FieldsDialog(
        title: 'Rename / Move',
        confirmLabel: 'Move',
        fields: [
          _FieldSpec(
            's3-move-folder',
            'Folder Path',
            'images/2024/',
            currentFolder,
          ),
          _FieldSpec('s3-move-name', 'File Name', 'photo.jpg', entry.name),
        ],
      ),
    );
    if (values == null || !mounted) return;
    final destKey = values[0] + values[1].trim();
    if (destKey == entry.key) return;
    if (destKey.isEmpty || destKey.endsWith('/')) {
      setState(() => _error = 'Invalid destination path');
      return;
    }

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
  }

  Future<void> _listObjects() async {
    if (_service == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _service!.listObjects(_prefix);
      entries.sort((a, b) {
        if (a.isPrefix != b.isPrefix) return a.isPrefix ? -1 : 1;
        return a.name.compareTo(b.name);
      });
      if (mounted) setState(() => _entries = entries);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _navigateTo(String prefix) {
    setState(() {
      _prefix = prefix;
      _breadcrumbs.clear();
      final parts = prefix.split('/').where((p) => p.isNotEmpty).toList();
      _breadcrumbs.addAll(parts);
    });
    _listObjects();
  }

  void _navigateUp() {
    if (_breadcrumbs.isEmpty) return;
    _breadcrumbs.removeLast();
    final newPrefix = _breadcrumbs.isEmpty ? '' : '${_breadcrumbs.join('/')}/';
    _navigateTo(newPrefix);
  }

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
      if (mounted) showYsToast(context, 'Uploaded ${file.name}');
    } catch (e) {
      if (mounted)
        setState(() {
          _uploadProgress = null;
          _error = e.toString();
        });
    }
  }

  Future<void> _delete(S3BucketEntry entry) async {
    final confirmed = await showYsConfirm(
      context,
      title: 'Delete object',
      message: 'Delete "${entry.name}"?',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _loading = true);
    try {
      await _service!.deleteObject(entry.key);
      await _listObjects();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copyDownloadUrl(S3BucketEntry entry) async {
    final url = _service!.presignedDownloadUrl(entry.key);
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) showYsToast(context, 'Download URL copied to clipboard');
  }

  Future<void> _openInBrowser(S3BucketEntry entry) async {
    final url = _service!.presignedDownloadUrl(entry.key);
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _download(S3BucketEntry entry) async {
    setState(() => _loading = true);
    try {
      final bytes = await _service!.downloadObject(entry.key);
      final path = '${_getDownloadsPath()}/${entry.name}';
      await File(path).writeAsBytes(bytes);
      if (mounted) showYsToast(context, 'Saved to Downloads/${entry.name}');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _getDownloadsPath() {
    if (Platform.isWindows) {
      return '${Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.'}\\Downloads';
    }
    return '${Platform.environment['HOME'] ?? '.'}/Downloads';
  }

  @override
  Widget build(BuildContext context) {
    final hasConfig = _configs.isNotEmpty && _activeIndex >= 0;
    return ColoredBox(
      color: YsColors.background,
      child: Column(
        children: [
          _buildToolbar(),
          const FDivider(),
          if (!hasConfig)
            Expanded(child: _buildEmptyState())
          else ...[
            _buildBreadcrumbs(),
            const FDivider(),
            if (_uploadProgress != null)
              FDeterminateProgress(
                value: _uploadProgress!,
                semanticsLabel: 'Upload progress',
              ),
            Expanded(child: _buildFileList()),
          ],
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    final hasConfig = _configs.isNotEmpty && _activeIndex >= 0;
    return Container(
      height: 48,
      color: YsColors.sidebar,
      padding: const EdgeInsets.symmetric(horizontal: YsSpace.s4),
      child: Row(
        children: [
          const Icon(
            FLucideIcons.cloud,
            size: 16,
            color: YsColors.mutedForeground,
          ),
          const SizedBox(width: YsSpace.s2),
          Expanded(
            child: hasConfig
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: _buildBucketSelector(),
                  )
                : const Text(
                    'S3 Browser',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: YsColors.foreground,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
          _toolBtn(FLucideIcons.plus, 'Add Bucket', () => _showConfigDialog()),
          if (hasConfig) ...[
            const SizedBox(width: YsSpace.s1),
            _toolBtn(FLucideIcons.folderPlus, 'New Folder', _createFolder),
            const SizedBox(width: YsSpace.s1),
            _toolBtn(FLucideIcons.upload, 'Upload', _upload),
            const SizedBox(width: YsSpace.s1),
            _toolBtn(FLucideIcons.refreshCw, 'Refresh', _listObjects),
          ],
        ],
      ),
    );
  }

  Widget _buildBucketSelector() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SizedBox(
            width: 220,
            child: FSelect<int>.rich(
              key: const ValueKey('s3-bucket-select'),
              size: .sm,
              control: .lifted(
                value: _activeIndex,
                onChange: (index) {
                  if (index != null && index != _activeIndex)
                    _activateConfig(index);
                },
              ),
              format: (i) => _configs[i].name,
              children: [
                for (final (i, c) in _configs.indexed)
                  FSelectItem<int>(
                    title: Text(
                      c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    value: i,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: YsSpace.s1),
        _toolBtn(
          FLucideIcons.pencil,
          'Edit Bucket',
          () => _showConfigDialog(
            existing: _configs[_activeIndex],
            editIndex: _activeIndex,
          ),
        ),
        const SizedBox(width: YsSpace.s1),
        _toolBtn(
          FLucideIcons.trash2,
          'Remove Bucket',
          () => _deleteConfig(_activeIndex),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return YsEmptyState(
      icon: FLucideIcons.cloud,
      title: 'No buckets configured',
      action: IntrinsicWidth(
        child: FButton(
          prefix: const Icon(FLucideIcons.plus),
          mainAxisSize: MainAxisSize.min,
          onPress: () => _showConfigDialog(),
          child: const Text('Add Bucket'),
        ),
      ),
    );
  }

  Widget _toolBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: FButton.icon(
        variant: .ghost,
        size: .xs,
        semanticsLabel: tooltip,
        onPress: onTap,
        child: Icon(icon),
      ),
    );
  }

  Widget _buildBreadcrumbs() {
    final bucketName = _activeIndex >= 0 ? _configs[_activeIndex].bucket : '';
    return Container(
      height: 40,
      color: YsColors.background,
      padding: const EdgeInsets.symmetric(horizontal: YsSpace.s2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _crumb(bucketName, _prefix.isEmpty ? null : () => _navigateTo('')),
            ..._breadcrumbs.asMap().entries.map((e) {
              final isLast = e.key == _breadcrumbs.length - 1;
              final partPrefix =
                  '${_breadcrumbs.sublist(0, e.key + 1).join('/')}/';
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '/',
                    style: TextStyle(
                      color: YsColors.mutedForeground,
                      fontSize: 12,
                    ),
                  ),
                  _crumb(
                    e.value,
                    isLast ? null : () => _navigateTo(partPrefix),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _crumb(String label, VoidCallback? onPress) {
    return FButton(
      variant: .ghost,
      size: .xs,
      mainAxisSize: MainAxisSize.min,
      onPress: onPress,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: onPress == null ? YsColors.foreground : YsColors.primary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildFileList() {
    if (_loading) {
      return const Center(child: FCircularProgress());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(YsSpace.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                FLucideIcons.circleAlert,
                color: YsColors.error,
                size: 32,
              ),
              const SizedBox(height: YsSpace.s2),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: YsColors.mutedForeground,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: YsSpace.s3),
              IntrinsicWidth(
                child: FButton(
                  variant: .outline,
                  size: .sm,
                  mainAxisSize: MainAxisSize.min,
                  onPress: _listObjects,
                  child: const Text('Retry'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return YsEmptyState(
        icon: FLucideIcons.folderOpen,
        title: 'Empty folder',
        action: _prefix.isNotEmpty
            ? IntrinsicWidth(
                child: FButton(
                  variant: .outline,
                  size: .sm,
                  mainAxisSize: MainAxisSize.min,
                  prefix: const Icon(FLucideIcons.arrowUp),
                  onPress: _navigateUp,
                  child: const Text('Go up'),
                ),
              )
            : null,
      );
    }

    return ListView.builder(
      itemCount: _entries.length + (_prefix.isNotEmpty ? 1 : 0),
      itemBuilder: (context, i) {
        if (_prefix.isNotEmpty && i == 0) {
          return FItem(
            prefix: const Icon(FLucideIcons.arrowUp, size: 16),
            title: const Text('..'),
            onPress: _navigateUp,
          );
        }
        final entry = _entries[_prefix.isNotEmpty ? i - 1 : i];
        return _EntryTile(
          key: ValueKey('s3-entry-${entry.key}'),
          entry: entry,
          onNavigate: entry.isPrefix ? () => _navigateTo(entry.key) : null,
          onDelete: entry.isPrefix ? null : () => _delete(entry),
          onCopyUrl: entry.isPrefix ? null : () => _copyDownloadUrl(entry),
          onOpenUrl: entry.isPrefix ? null : () => _openInBrowser(entry),
          onDownload: entry.isPrefix ? null : () => _download(entry),
          onRenameMove: entry.isPrefix ? null : () => _renameMove(entry),
        );
      },
    );
  }
}

class _FieldSpec {
  final String key;
  final String label;
  final String hint;
  final String initial;
  final bool obscure;
  const _FieldSpec(
    this.key,
    this.label,
    this.hint,
    this.initial, {
    this.obscure = false,
  });
}

/// A dialog of labelled text fields that owns its controllers and pops the
/// entered values (in field order), or null on Cancel.
class _FieldsDialog extends StatefulWidget {
  final String title;
  final String confirmLabel;
  final List<_FieldSpec> fields;
  const _FieldsDialog({
    required this.title,
    required this.confirmLabel,
    required this.fields,
  });

  @override
  State<_FieldsDialog> createState() => _FieldsDialogState();
}

class _FieldsDialogState extends State<_FieldsDialog> {
  late final List<TextEditingController> _ctrls = [
    for (final f in widget.fields) TextEditingController(text: f.initial),
  ];

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YsDialog(
      title: widget.title,
      body: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, f) in widget.fields.indexed)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i == widget.fields.length - 1 ? 0 : YsSpace.s3,
                  ),
                  child: FTextField(
                    key: ValueKey(f.key),
                    control: .managed(controller: _ctrls[i]),
                    label: Text(f.label),
                    hint: f.hint,
                    obscureText: f.obscure,
                    autofocus: i == 0,
                    autocorrect: false,
                    enableSuggestions: false,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        FButton(
          variant: .outline,
          onPress: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FButton(
          onPress: () =>
              Navigator.pop(context, [for (final c in _ctrls) c.text]),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _EntryTile extends StatefulWidget {
  final S3BucketEntry entry;
  final VoidCallback? onNavigate;
  final VoidCallback? onDelete;
  final VoidCallback? onCopyUrl;
  final VoidCallback? onOpenUrl;
  final VoidCallback? onDownload;
  final VoidCallback? onRenameMove;

  const _EntryTile({
    super.key,
    required this.entry,
    this.onNavigate,
    this.onDelete,
    this.onCopyUrl,
    this.onOpenUrl,
    this.onDownload,
    this.onRenameMove,
  });

  @override
  State<_EntryTile> createState() => _EntryTileState();
}

class _EntryTileState extends State<_EntryTile> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final hasActions = !entry.isPrefix;
    // Actions are always built (so Tab reaches them); they are painted only
    // while the row is hovered or one of them holds focus.
    final showActions = _hovered || _focused;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (f) => setState(() => _focused = f),
        child: FItem(
          prefix: Icon(
            entry.isPrefix ? FLucideIcons.folder : _fileIcon(entry.name),
            size: 16,
            color: entry.isPrefix ? YsColors.warn : YsColors.mutedForeground,
          ),
          title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: !entry.isPrefix && entry.lastModified != null
              ? Text(
                  '${_fmtDate(entry.lastModified!)}  •  ${entry.displaySize}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          onPress: widget.onNavigate,
          suffix: hasActions
              // Always built so Tab can focus them (focus reveals them); while
              // hidden they are not hit-testable and not in semantics.
              ? IgnorePointer(
                  ignoring: !showActions,
                  child: ExcludeSemantics(
                    excluding: !showActions,
                    child: Opacity(
                      opacity: showActions ? 1 : 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.onCopyUrl != null)
                            _actionBtn(
                              FLucideIcons.link,
                              'Copy URL',
                              widget.onCopyUrl!,
                            ),
                          if (widget.onOpenUrl != null)
                            _actionBtn(
                              FLucideIcons.externalLink,
                              'Open',
                              widget.onOpenUrl!,
                            ),
                          if (widget.onDownload != null)
                            _actionBtn(
                              FLucideIcons.download,
                              'Download',
                              widget.onDownload!,
                            ),
                          if (widget.onRenameMove != null)
                            _actionBtn(
                              FLucideIcons.pencilLine,
                              'Rename / Move',
                              widget.onRenameMove!,
                            ),
                          if (widget.onDelete != null)
                            _actionBtn(
                              FLucideIcons.trash2,
                              'Delete',
                              widget.onDelete!,
                              color: YsColors.error,
                            ),
                        ],
                      ),
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _actionBtn(
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: YsSpace.s1),
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: FButton.icon(
          variant: .ghost,
          size: .xs,
          semanticsLabel: tooltip,
          onPress: onTap,
          child: Icon(icon, color: color),
        ),
      ),
    );
  }

  IconData _fileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' ||
      'jpeg' ||
      'png' ||
      'gif' ||
      'webp' ||
      'svg' => FLucideIcons.image,
      'mp4' || 'avi' || 'mov' || 'mkv' => FLucideIcons.fileVideo,
      'mp3' || 'wav' || 'ogg' || 'flac' => FLucideIcons.fileAudio,
      'pdf' => FLucideIcons.fileText,
      'zip' || 'tar' || 'gz' || '7z' || 'rar' => FLucideIcons.fileArchive,
      'js' ||
      'ts' ||
      'dart' ||
      'py' ||
      'go' ||
      'rs' ||
      'sh' => FLucideIcons.fileCode,
      'json' || 'yaml' || 'yml' || 'toml' || 'xml' => FLucideIcons.fileJson,
      'md' || 'txt' || 'log' || 'csv' => FLucideIcons.fileText,
      _ => FLucideIcons.file,
    };
  }

  String _fmtDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
