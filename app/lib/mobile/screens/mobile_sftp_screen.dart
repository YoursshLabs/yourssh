import 'dart:io' as io;

import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../models/host.dart';
import '../../services/sftp_transfer_service.dart';
import '../../services/ssh_service.dart';
import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';

/// Contextual SFTP browser — reached from the Terminal ⋮ menu for the
/// currently active session's host. One SFTP channel is reused for all
/// operations; a load-token prevents stale results from a slow listdir
/// overwriting a newer navigation.
class MobileSftpScreen extends StatefulWidget {
  final Host host;

  /// Optional override for directory listing — injected in tests so the widget
  /// tree can be pumped without a real SSH connection.
  final Future<List<SftpName>> Function(String path)? lister;

  const MobileSftpScreen({
    super.key,
    required this.host,
    this.lister,
  });

  @override
  State<MobileSftpScreen> createState() => _MobileSftpScreenState();
}

enum _SortField { name, size }

class _MobileSftpScreenState extends State<MobileSftpScreen> {
  String _path = '.';
  List<SftpName> _entries = [];
  bool _loading = false;
  String? _error;

  // One reusable SFTP channel per host (opening one per listdir/download adds a
  // full channel-handshake RTT to every tap on a mobile link).
  SftpClient? _sftp;
  // Monotonic token so a slow listdir from a previous path can't overwrite the
  // current view when the user navigates quickly.
  int _loadToken = 0;

  _SortField _sortField = _SortField.name;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load('.'));
  }

  @override
  void dispose() {
    _sftp?.close();
    super.dispose();
  }

  Future<SftpClient> _client() async {
    if (_sftp != null) return _sftp!;
    _sftp = await context.read<SshService>().openSftp(widget.host);
    return _sftp!;
  }

  Future<List<SftpName>> _listDir(String path) async {
    if (widget.lister != null) return widget.lister!(path);
    final sftp = await _client();
    return sftp.listdir(path);
  }

  Future<void> _load(String path) async {
    final token = ++_loadToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _listDir(path);
      if (!mounted || token != _loadToken) return;
      final entries = raw
          .where((e) => e.filename != '.' && e.filename != '..')
          .toList();
      _sortEntries(entries);
      setState(() {
        _path = path;
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (mounted && token == _loadToken) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  void _sortEntries(List<SftpName> list) {
    list.sort((a, b) {
      final ad = a.attr.isDirectory, bd = b.attr.isDirectory;
      // Directories always first regardless of sort field.
      if (ad != bd) return ad ? -1 : 1;
      int cmp;
      if (_sortField == _SortField.size) {
        cmp = (a.attr.size ?? 0).compareTo(b.attr.size ?? 0);
      } else {
        cmp = a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
      }
      return _sortAscending ? cmp : -cmp;
    });
  }

  void _applySort() {
    final sorted = List<SftpName>.from(_entries);
    _sortEntries(sorted);
    setState(() => _entries = sorted);
  }

  // ── Breadcrumb helpers ────────────────────────────────────────────────────

  List<String> get _parts =>
      _path == '.' ? [] : _path.split('/').where((s) => s.isNotEmpty).toList();

  String _join(String name) =>
      _path == '.' ? name : p.posix.join(_path, name);

  // ── Size formatting ───────────────────────────────────────────────────────

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }

  static String _totalSize(List<SftpName> entries) {
    final total =
        entries.fold<int>(0, (s, e) => s + (e.attr.size ?? 0));
    return _fmtSize(total);
  }

  // ── Icon selection ────────────────────────────────────────────────────────

  IconData _iconFor(SftpName e) {
    final name = e.filename;
    final lower = name.toLowerCase();
    if (e.attr.isDirectory) return Icons.folder_rounded;
    // Sensitive / dot-files get a lock glyph.
    if (name.startsWith('.') || lower.contains('secret') ||
        lower.contains('credential') || lower.contains('passwd') ||
        lower.endsWith('.pem') || lower.endsWith('.key') ||
        lower.endsWith('.env')) {
      return Icons.lock_outline;
    }
    if (RegExp(r'\.(zip|tar|gz|tgz|bz2|xz|7z|rar)$').hasMatch(lower)) {
      return Icons.folder_zip_outlined;
    }
    if (RegExp(r'\.(png|jpe?g|gif|webp|svg|bmp|ico)$').hasMatch(lower)) {
      return Icons.image_outlined;
    }
    if (RegExp(r'\.(mp4|mov|avi|mkv|webm)$').hasMatch(lower)) {
      return Icons.videocam_outlined;
    }
    if (RegExp(r'\.(sh|bash|zsh|py|js|ts|go|rs|c|cpp|dart|rb|json|ya?ml|toml|conf|ini|cfg)$')
        .hasMatch(lower)) {
      return Icons.description_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Color _iconColor(SftpName e) {
    if (e.attr.isDirectory) return MobileColors.blue;
    final name = e.filename.toLowerCase();
    if (e.filename.startsWith('.') || name.endsWith('.pem') ||
        name.endsWith('.key') || name.endsWith('.env') ||
        name.contains('secret') || name.contains('passwd')) {
      return MobileColors.yellow;
    }
    return MobileColors.textMuted;
  }

  // ── Transfer ops ──────────────────────────────────────────────────────────

  Future<void> _download(SftpName e) async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    final sink = io.File(p.join(dir, e.filename)).openWrite();
    try {
      final sftp = await _client();
      final file = await sftp.open(_join(e.filename));
      await for (final chunk in file.read()) {
        sink.add(chunk);
      }
      await file.close();
      _snack('Downloaded ${e.filename}');
    } catch (err) {
      _snack('Download failed: $err');
    } finally {
      await sink.close();
    }
  }

  Future<void> _upload() async {
    final transfer = context.read<SftpTransferService>();
    final picked = await FilePicker.platform.pickFiles();
    final localPath =
        picked == null || picked.files.isEmpty ? null : picked.files.first.path;
    if (localPath == null) return;
    final name = p.basename(localPath);
    try {
      await transfer.uploadFile(widget.host, localPath, _join(name));
      _snack('Uploaded $name');
      _load(_path);
    } catch (err) {
      _snack('Upload failed: $err');
    }
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MobileColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              host: widget.host,
              onBack: () => Navigator.maybePop(context),
              onUpload: _upload,
              onRefresh: () => _load(_path),
            ),
            _BreadcrumbRow(
              parts: _parts,
              onHome: _parts.isEmpty ? null : () => _load('.'),
              onSegment: (i) =>
                  _load('/${_parts.sublist(0, i + 1).join('/')}'),
            ),
            _MetaRow(
              count: _entries.length,
              totalSize: _totalSize(_entries),
              sortField: _sortField,
              ascending: _sortAscending,
              onSort: (field, asc) {
                setState(() {
                  _sortField = field;
                  _sortAscending = asc;
                });
                _applySort();
              },
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: MobileTokens.space4,
                    vertical: MobileTokens.space2),
                child: Text(
                  _error!,
                  style: mobileBody(size: 12, color: MobileColors.red),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: MobileColors.accent))
                  : _entries.isEmpty
                      ? Center(
                          child: Text(
                            'Empty folder',
                            style:
                                mobileBody(color: MobileColors.textMuted),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _entries.length,
                          separatorBuilder: (context, i) => Padding(
                            padding:
                                const EdgeInsets.only(left: 47),
                            child: Divider(
                              height: 1,
                              thickness: 0.5,
                              color: MobileColors.border,
                            ),
                          ),
                          itemBuilder: (_, i) => _EntryRow(
                            entry: _entries[i],
                            icon: _iconFor(_entries[i]),
                            iconColor: _iconColor(_entries[i]),
                            onTap: _entries[i].attr.isDirectory
                                ? () =>
                                    _load(_join(_entries[i].filename))
                                : null,
                            onDownload: _entries[i].attr.isDirectory
                                ? null
                                : () => _download(_entries[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header ─────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final Host host;
  final VoidCallback onBack;
  final VoidCallback onUpload;
  final VoidCallback onRefresh;

  const _Header({
    required this.host,
    required this.onBack,
    required this.onUpload,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      color: MobileColors.surfaceAlt,
      child: Row(
        children: [
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                color: MobileColors.accent, size: 20),
            onPressed: onBack,
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Files',
                  style: mobileBody(
                      size: 11,
                      color: MobileColors.textMuted,
                      weight: FontWeight.w500),
                ),
                Text(
                  host.label,
                  style: mobileBody(
                      size: 14, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.upload_file_outlined,
                color: MobileColors.textMuted, size: 20),
            tooltip: 'Upload',
            onPressed: onUpload,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert,
                color: MobileColors.textMuted, size: 20),
            tooltip: 'More',
            onPressed: () => _showMenu(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MobileColors.surfaceAlt,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: MobileColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.refresh,
                  color: MobileColors.textPrimary),
              title: Text('Refresh',
                  style: mobileBody(color: MobileColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                onRefresh();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Breadcrumb row ──────────────────────────────────────────────────────────

class _BreadcrumbRow extends StatelessWidget {
  final List<String> parts;
  final VoidCallback? onHome;
  final void Function(int segmentIndex) onSegment;

  const _BreadcrumbRow({
    required this.parts,
    required this.onHome,
    required this.onSegment,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      color: MobileColors.surfaceAlt,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: MobileTokens.space4),
        child: Row(
          children: [
            // Home icon — tappable when not at root.
            GestureDetector(
              onTap: onHome,
              child: Icon(
                Icons.home_outlined,
                size: 16,
                color: parts.isEmpty
                    ? MobileColors.textPrimary
                    : MobileColors.accent,
              ),
            ),
            for (var i = 0; i < parts.length; i++) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: Icon(Icons.chevron_right,
                    size: 14, color: MobileColors.textFaint),
              ),
              GestureDetector(
                onTap: i == parts.length - 1
                    ? null
                    : () => onSegment(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    parts[i],
                    style: mobileMono(
                      size: 13,
                      color: i == parts.length - 1
                          ? MobileColors.textPrimary
                          : MobileColors.accent,
                      weight: i == parts.length - 1
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Meta row (count + sort) ─────────────────────────────────────────────────

class _MetaRow extends StatelessWidget {
  final int count;
  final String totalSize;
  final _SortField sortField;
  final bool ascending;
  final void Function(_SortField field, bool ascending) onSort;

  const _MetaRow({
    required this.count,
    required this.totalSize,
    required this.sortField,
    required this.ascending,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      color: MobileColors.surfaceAlt,
      padding: const EdgeInsets.symmetric(horizontal: MobileTokens.space4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$count item${count == 1 ? '' : 's'} · $totalSize',
              style: mobileMono(size: 11, color: MobileColors.textMuted),
            ),
          ),
          GestureDetector(
            onTap: () {
              // Cycle: name↑ → name↓ → size↑ → size↓ → name↑
              if (sortField == _SortField.name && ascending) {
                onSort(_SortField.name, false);
              } else if (sortField == _SortField.name && !ascending) {
                onSort(_SortField.size, true);
              } else if (sortField == _SortField.size && ascending) {
                onSort(_SortField.size, false);
              } else {
                onSort(_SortField.name, true);
              }
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sortField == _SortField.name ? 'Name' : 'Size',
                  style: mobileBody(
                      size: 12, color: MobileColors.textMuted),
                ),
                const SizedBox(width: 2),
                Icon(
                  ascending
                      ? Icons.arrow_upward
                      : Icons.arrow_downward,
                  size: 12,
                  color: MobileColors.textMuted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Entry row ───────────────────────────────────────────────────────────────

class _EntryRow extends StatelessWidget {
  final SftpName entry;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;
  final VoidCallback? onDownload;

  const _EntryRow({
    required this.entry,
    required this.icon,
    required this.iconColor,
    this.onTap,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final isDir = entry.attr.isDirectory;
    final isDotFile = entry.filename.startsWith('.');
    final nameStyle = isDotFile
        ? mobileMono(size: 14, color: MobileColors.textPrimary)
        : mobileBody(size: 14, color: MobileColors.textPrimary);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: MobileTokens.space4, vertical: MobileTokens.space3),
        child: Row(
          children: [
            // Icon column — fixed width so names align.
            SizedBox(
              width: 32,
              child: Icon(icon, size: 22, color: iconColor),
            ),
            const SizedBox(width: MobileTokens.space2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.filename, style: nameStyle),
                  if (!isDir && entry.attr.size != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _MobileSftpScreenState._fmtSize(entry.attr.size!),
                      style: mobileMono(
                          size: 11, color: MobileColors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            if (isDir)
              const Icon(Icons.chevron_right,
                  size: 18, color: MobileColors.textFaint)
            else if (onDownload != null)
              GestureDetector(
                onTap: onDownload,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.download_outlined,
                      size: 18, color: MobileColors.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
