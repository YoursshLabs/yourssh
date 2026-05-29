import 'dart:async';
import 'dart:io' as io;
import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../services/ssh_service.dart';
import '../theme/app_theme.dart';

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
    final localPath = p.join(saveDir, entry.filename);

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

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: Column(
        children: [
          _buildTopBar(),
          if (_status.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: AppColors.sidebar,
              child: Text(_status, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                : _buildFileList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 16, color: AppColors.textSecondary),
            onPressed: _remotePath == '/' ? null : () => _loadDir(p.posix.dirname(_remotePath)),
            tooltip: 'Go up',
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '${widget.host.label} — $_remotePath',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 16, color: AppColors.textSecondary),
            onPressed: () => _loadDir(_remotePath),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: _upload,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(6)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.upload, size: 13, color: Colors.black),
                  SizedBox(width: 5),
                  Text('UPLOAD', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList() {
    if (_sftp == null) {
      return const Center(child: Text('Not connected', style: TextStyle(color: AppColors.textSecondary)));
    }
    if (_remoteEntries.isEmpty) {
      return const Center(child: Text('Empty directory', style: TextStyle(color: AppColors.textTertiary)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _remoteEntries.length,
      itemBuilder: (_, i) => _FileRow(
        entry: _remoteEntries[i],
        onTap: () => _navigate(_remoteEntries[i]),
        onDownload: () => _download(_remoteEntries[i]),
      ),
    );
  }
}

class _FileRow extends StatefulWidget {
  final SftpName entry;
  final VoidCallback onTap;
  final VoidCallback onDownload;
  const _FileRow({required this.entry, required this.onTap, required this.onDownload});

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final isDir = entry.attr.isDirectory;
    final size = entry.attr.size;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onDoubleTap: widget.onTap,
        child: Container(
          height: 36,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.cardHover : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(
                isDir ? Icons.folder : Icons.insert_drive_file_outlined,
                size: 15,
                color: isDir ? AppColors.orange : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.filename,
                  style: TextStyle(
                    color: isDir ? AppColors.textPrimary : AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isDir && size != null)
                Text(
                  _formatSize(size),
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
                ),
              if (_hovered && !isDir) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: widget.onDownload,
                  child: const Icon(Icons.download, size: 14, color: AppColors.accent),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}K';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}M';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}G';
  }
}
