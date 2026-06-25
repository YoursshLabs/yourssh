import 'dart:io' as io;

import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../models/host.dart';
import '../../providers/session_provider.dart';
import '../../services/sftp_transfer_service.dart';
import '../../services/ssh_service.dart';
import '../../theme/app_theme.dart';

/// Single-panel SFTP browser over the active SSH session's host. Lists, opens
/// directories, downloads files to a picked folder, and uploads a picked file.
/// One SFTP channel is held per host and reused for all operations.
class MobileSftpScreen extends StatefulWidget {
  const MobileSftpScreen({super.key});

  @override
  State<MobileSftpScreen> createState() => _MobileSftpScreenState();
}

class _MobileSftpScreenState extends State<MobileSftpScreen> {
  String _path = '.';
  List<SftpName> _entries = [];
  bool _loading = false;
  String? _error;
  String? _loadedHostId;

  // One reusable SFTP channel per host (opening one per listdir/download adds a
  // full channel-handshake RTT to every tap on a mobile link).
  SftpClient? _sftp;
  String? _sftpHostId;
  // Monotonic token so a slow listdir from a previous host can't overwrite the
  // current view when the user switches sessions mid-load.
  int _loadToken = 0;

  @override
  void dispose() {
    _sftp?.close();
    super.dispose();
  }

  Future<SftpClient> _client(Host host) async {
    if (_sftp != null && _sftpHostId == host.id) return _sftp!;
    _sftp?.close();
    _sftp = await context.read<SshService>().openSftp(host);
    _sftpHostId = host.id;
    return _sftp!;
  }

  Future<void> _load(Host host, String path) async {
    final token = ++_loadToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sftp = await _client(host);
      final raw = await sftp.listdir(path);
      raw.sort((a, b) {
        final ad = a.attr.isDirectory, bd = b.attr.isDirectory;
        if (ad != bd) return ad ? -1 : 1;
        // Case-insensitive, matching the desktop SFTP ordering.
        return a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
      });
      if (!mounted || token != _loadToken) return; // a newer load supersedes us
      setState(() {
        _path = path;
        _entries = raw
            .where((e) => e.filename != '.' && e.filename != '..')
            .toList();
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

  void _maybeLoad(Host host) {
    if (_loadedHostId == host.id) return;
    _loadedHostId = host.id;
    _path = '.';
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(host, '.'));
  }

  @override
  Widget build(BuildContext context) {
    final active = context.watch<SessionProvider>().activeSshSession;
    if (active == null) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Text('Connect a host to browse files',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    final host = active.host;
    _maybeLoad(host);

    return Scaffold(
      backgroundColor: AppColors.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _upload(host),
        backgroundColor: AppColors.accent,
        child: const Icon(Icons.upload_file, color: Colors.black),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _bar(host),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!,
                    style: const TextStyle(color: AppColors.red, fontSize: 12)),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _entries.length,
                      itemBuilder: (_, i) => _row(host, _entries[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(Host host) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: AppColors.card,
      child: Row(
        children: [
          IconButton(
            icon:
                const Icon(Icons.arrow_upward, color: AppColors.textSecondary),
            onPressed: _path == '.' || _path == '/'
                ? null
                : () => _load(host, p.posix.dirname(_path)),
          ),
          Expanded(
            child: Text(_path,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
            onPressed: () => _load(host, _path),
          ),
        ],
      ),
    );
  }

  Widget _row(Host host, SftpName e) {
    final isDir = e.attr.isDirectory;
    return ListTile(
      leading: Icon(isDir ? Icons.folder : Icons.insert_drive_file,
          color: isDir ? AppColors.accent : AppColors.textSecondary),
      title:
          Text(e.filename, style: const TextStyle(color: AppColors.textPrimary)),
      subtitle: isDir
          ? null
          : Text('${e.attr.size ?? 0} bytes',
              style:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      trailing: isDir
          ? null
          : IconButton(
              icon: const Icon(Icons.download, color: AppColors.textSecondary),
              onPressed: () => _download(host, e),
            ),
      onTap: isDir ? () => _load(host, _join(e.filename)) : null,
    );
  }

  String _join(String name) => _path == '.' ? name : p.posix.join(_path, name);

  Future<void> _download(Host host, SftpName e) async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null) return;
    final sink = io.File(p.join(dir, e.filename)).openWrite();
    try {
      final sftp = await _client(host);
      final file = await sftp.open(_join(e.filename));
      // Stream chunks to disk instead of buffering the whole file in memory.
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

  Future<void> _upload(Host host) async {
    final transfer = context.read<SftpTransferService>();
    final picked = await FilePicker.platform.pickFiles();
    final localPath =
        picked == null || picked.files.isEmpty ? null : picked.files.first.path;
    if (localPath == null) return;
    final name = p.basename(localPath);
    try {
      await transfer.uploadFile(host, localPath, _join(name));
      _snack('Uploaded $name');
      _load(host, _path);
    } catch (err) {
      _snack('Upload failed: $err');
    }
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }
}
