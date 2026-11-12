import 'dart:async';
import 'dart:io' as io;
import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../services/ssh_service.dart';
import '../util/safe_local_path.dart';
import 'file_panel_chrome.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

class SftpScreen extends StatefulWidget {
  final Host host;
  const SftpScreen({super.key, required this.host});

  @override
  State<SftpScreen> createState() => _SftpScreenState();
}

class _SftpScreenState extends State<SftpScreen> {
  SftpClient? _sftp;
  String _remotePath = '/';
  List<SftpName> _remoteEntries = [];
  String _status = 'Connecting…';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _sftp?.close();
    super.dispose();
  }

  Future<void> _connect() async {
    final ssh = context.read<SshService>();
    try {
      final sftp = await ssh.openSftp(widget.host);
      if (!mounted) return;
      setState(() { _sftp = sftp; _status = ''; });
      await _loadDir('/');
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _loadDir(String path) async {
    final sftp = _sftp;
    if (sftp == null) return;
    setState(() { _loading = true; _status = 'Loading…'; });
    try {
      final entries = await sftp.listdir(path);
      entries.sort((a, b) {
        final aDir = a.attr.isDirectory;
        final bDir = b.attr.isDirectory;
        if (aDir != bDir) return aDir ? -1 : 1;
        return a.filename.compareTo(b.filename);
      });
      if (mounted) {
        setState(() {
          _remotePath = path;
          _remoteEntries = entries.where((e) => e.filename != '.').toList();
          _loading = false;
          _status = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _status = 'Error: $e'; });
    }
  }

  Future<void> _download(SftpName entry) async {
    final sftp = _sftp;
    if (sftp == null) return;
    final saveDir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Save to folder');
    if (saveDir == null) return;

    final remotePath = p.posix.join(_remotePath, entry.filename);
    final String localPath;
    try {
      localPath = safeLocalChild(saveDir, entry.filename);
    } on UnsafeRemotePathException catch (e) {
      setState(() => _status = 'Error: $e');
      return;
    }

    setState(() => _status = 'Downloading ${entry.filename}…');
    try {
      final file = await sftp.open(remotePath);
      final bytes = await file.readBytes();
      await file.close();
      await io.File(localPath).writeAsBytes(bytes);
      if (mounted) setState(() => _status = 'Downloaded to $localPath');
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _upload() async {
    final sftp = _sftp;
    if (sftp == null) return;
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final localFile = io.File(result.files.first.path!);
    final remoteName = p.basename(localFile.path);
    final remotePath = p.posix.join(_remotePath, remoteName);

    setState(() => _status = 'Uploading $remoteName…');
    try {
      final bytes = await localFile.readAsBytes();
      final remote = await sftp.open(remotePath, mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate);
      await remote.writeBytes(bytes);
      await remote.close();
      if (mounted) {
        setState(() => _status = 'Uploaded $remoteName');
        await _loadDir(_remotePath);
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: $e');
    }
  }

  void _navigate(SftpName entry) {
    final isDir = entry.attr.isDirectory;
    if (!isDir) {
      _download(entry);
      return;
    }
    final newPath = entry.filename == '..'
        ? p.posix.dirname(_remotePath)
        : p.posix.join(_remotePath, entry.filename);
    _loadDir(newPath);
  }

  /// Built once: cells depend only on the entry (see YsColumn.cell).
  late final List<YsColumn<SftpName>> _columns = [
    YsColumn<SftpName>(
      id: 'name',
      label: 'Name',
      flex: 5,
      cell: (_, e) => FileNameCell(
        name: e.filename,
        isDirectory: e.attr.isDirectory,
        extension: p.posix.extension(e.filename).replaceFirst('.', ''),
      ),
    ),
    YsColumn<SftpName>(
      id: 'size',
      label: 'Size',
      width: 70,
      numeric: true,
      cell: (_, e) => FileMetaCell(
          e.attr.isDirectory || e.attr.size == null
              ? ''
              : _formatSize(e.attr.size!)),
    ),
    YsColumn<SftpName>(
      id: 'download',
      label: '',
      width: 40,
      cell: (_, e) => e.attr.isDirectory
          ? const SizedBox.shrink()
          : FilePanelIconButton(
              icon: FLucideIcons.download,
              tooltip: 'Download',
              onPress: () => _download(e),
            ),
    ),
  ];

  /// The clicked row, highlighted.
  SftpName? _selected;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: YsColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopBar(),
          if (_status.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: YsSpace.s4, vertical: 6),
              color: YsColors.sidebar,
              child: Text(
                _status,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: YsColors.mutedForeground, fontSize: 12),
              ),
            ),
          Expanded(child: _buildFileList()),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: YsColors.sidebar,
        border: Border(bottom: BorderSide(color: YsColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: YsSpace.s4),
      child: Row(
        children: [
          FilePanelIconButton(
            icon: FLucideIcons.arrowUp,
            tooltip: 'Go up',
            onPress: _remotePath == '/'
                ? null
                : () => _loadDir(p.posix.dirname(_remotePath)),
          ),
          const SizedBox(width: YsSpace.s1),
          Expanded(
            child: Text(
              '${widget.host.label} — $_remotePath',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: YsColors.foreground, fontSize: 13),
            ),
          ),
          FilePanelIconButton(
            icon: FLucideIcons.refreshCw,
            tooltip: 'Refresh',
            onPress: () => _loadDir(_remotePath),
          ),
          const SizedBox(width: YsSpace.s1),
          FButton(
            size: .xs,
            mainAxisSize: MainAxisSize.min,
            onPress: _upload,
            prefix: const Icon(FLucideIcons.upload),
            child: const Text('Upload'),
          ),
          const SizedBox(width: YsSpace.s1),
          FilePanelIconButton(
            icon: FLucideIcons.x,
            tooltip: 'Close',
            onPress: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList() {
    // The table stays mounted while a folder loads so it keeps keyboard
    // focus across Enter / double-click navigation.
    final ready = _sftp != null && !_loading;
    return Padding(
      padding: const EdgeInsets.all(YsSpace.s2),
      child: YsFileTable<SftpName>(
        rows: ready ? _remoteEntries : const <SftpName>[],
        rowKey: (e) => e.filename,
        emptyState: _loading
            ? const Center(child: FCircularProgress())
            : FilePanelMessage(
                _sftp == null ? 'Not connected' : 'Empty directory'),
        columns: _columns,
        selected: {?_selected},
        onSelect: (e, {additive = false, range = false}) =>
            setState(() => _selected = e),
        // Double-click / Enter: folders (and "..") navigate, files download.
        onOpen: _navigate,
        rowLabel: (e) => e.filename,
      ),
    );
  }
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}K';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}M';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}G';
}
