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

class S3BrowserScreen extends StatefulWidget {
  const S3BrowserScreen({super.key});

  @override
  State<S3BrowserScreen> createState() => _S3BrowserScreenState();
}

class _S3BrowserScreenState extends State<S3BrowserScreen> {
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Uploaded ${file.name}')),
        );
      }
    } catch (e) {
      if (mounted) setState(() { _uploadProgress = null; _error = e.toString(); });
    }
  }

  Future<void> _delete(S3BucketEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('Delete object', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('Delete "${entry.name}"?',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download URL copied to clipboard')),
      );
    }
  }

  Future<void> _openInBrowser(S3BucketEntry entry) async {
    final url = _service!.presignedDownloadUrl(entry.key);
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

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
            child: Text(e.value.name),
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

  Widget _toolBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildBreadcrumbs() {
    final bucketName = _activeIndex >= 0 ? _configs[_activeIndex].bucket : '';
    return Container(
      height: 36,
      color: AppColors.bg,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          InkWell(
            onTap: _prefix.isEmpty ? null : () => _navigateTo(''),
            child: Text(
              bucketName,
              style: TextStyle(
                color: _prefix.isEmpty ? AppColors.textPrimary : AppColors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ..._breadcrumbs.asMap().entries.map((e) {
            final isLast = e.key == _breadcrumbs.length - 1;
            final partPrefix = '${_breadcrumbs.sublist(0, e.key + 1).join('/')}/';
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(' / ', style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
                InkWell(
                  onTap: isLast ? null : () => _navigateTo(partPrefix),
                  child: Text(
                    e.value,
                    style: TextStyle(
                      color: isLast ? AppColors.textPrimary : AppColors.accent,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildFileList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppColors.red, size: 32),
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 12),
            TextButton(onPressed: _listObjects, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open_outlined, color: AppColors.textTertiary, size: 40),
            const SizedBox(height: 8),
            const Text('Empty folder', style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
            if (_prefix.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.arrow_upward, size: 14),
                label: const Text('Go up'),
                onPressed: _navigateUp,
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _entries.length + (_prefix.isNotEmpty ? 1 : 0),
      itemBuilder: (context, i) {
        if (_prefix.isNotEmpty && i == 0) {
          return ListTile(
            dense: true,
            leading: const Icon(Icons.arrow_upward, size: 16, color: AppColors.textTertiary),
            title: const Text('..', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            onTap: _navigateUp,
          );
        }
        final entry = _entries[_prefix.isNotEmpty ? i - 1 : i];
        return _EntryTile(
          entry: entry,
          onNavigate: entry.isPrefix ? () => _navigateTo(entry.key) : null,
          onDelete: entry.isPrefix ? null : () => _delete(entry),
          onCopyUrl: entry.isPrefix ? null : () => _copyDownloadUrl(entry),
          onOpenUrl: entry.isPrefix ? null : () => _openInBrowser(entry),
        );
      },
    );
  }

  Widget _field(TextEditingController ctrl, String label, String hint, {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            obscureText: obscure,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
              filled: true,
              fillColor: AppColors.card,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatefulWidget {
  final S3BucketEntry entry;
  final VoidCallback? onNavigate;
  final VoidCallback? onDelete;
  final VoidCallback? onCopyUrl;
  final VoidCallback? onOpenUrl;

  const _EntryTile({
    required this.entry,
    this.onNavigate,
    this.onDelete,
    this.onCopyUrl,
    this.onOpenUrl,
  });

  @override
  State<_EntryTile> createState() => _EntryTileState();
}

class _EntryTileState extends State<_EntryTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        color: _hovered ? AppColors.card.withValues(alpha: 0.6) : Colors.transparent,
        child: ListTile(
          dense: true,
          leading: Icon(
            entry.isPrefix ? Icons.folder_outlined : _fileIcon(entry.name),
            size: 16,
            color: entry.isPrefix ? const Color(0xFFE8B84D) : AppColors.textSecondary,
          ),
          title: Text(entry.name,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          subtitle: !entry.isPrefix && entry.lastModified != null
              ? Text(
                  '${_fmtDate(entry.lastModified!)}  •  ${entry.displaySize}',
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
                )
              : null,
          onTap: widget.onNavigate,
          trailing: _hovered && !entry.isPrefix
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onCopyUrl != null)
                      _actionBtn(Icons.link_outlined, 'Copy URL', widget.onCopyUrl!),
                    if (widget.onOpenUrl != null)
                      _actionBtn(Icons.open_in_browser_outlined, 'Open', widget.onOpenUrl!),
                    if (widget.onDelete != null)
                      _actionBtn(Icons.delete_outlined, 'Delete', widget.onDelete!, color: AppColors.red),
                  ],
                )
              : null,
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String tooltip, VoidCallback onTap, {Color? color}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: color ?? AppColors.textSecondary),
        ),
      ),
    );
  }

  IconData _fileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'svg' => Icons.image_outlined,
      'mp4' || 'avi' || 'mov' || 'mkv' => Icons.video_file_outlined,
      'mp3' || 'wav' || 'ogg' || 'flac' => Icons.audio_file_outlined,
      'pdf' => Icons.picture_as_pdf_outlined,
      'zip' || 'tar' || 'gz' || '7z' || 'rar' => Icons.archive_outlined,
      'js' || 'ts' || 'dart' || 'py' || 'go' || 'rs' || 'sh' => Icons.code_outlined,
      'json' || 'yaml' || 'yml' || 'toml' || 'xml' => Icons.data_object_outlined,
      'md' || 'txt' || 'log' || 'csv' => Icons.description_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }

  String _fmtDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
