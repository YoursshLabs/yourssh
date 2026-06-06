// app/lib/widgets/bulk/bulk_push_dialog.dart
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/bulk_result.dart';
import '../../models/host.dart';
import '../../services/bulk_action_service.dart';
import '../../services/sftp_file_ops_service.dart';
import '../../services/sftp_transfer_service.dart';
import '../../services/ssh_service.dart';
import '../../theme/app_theme.dart';
import '../../util/bulk_format.dart';
import 'bulk_host_status_list.dart';
import 'bulk_run_controller.dart';

/// Modal that uploads local files/folders to the same remote path on N
/// hosts. Existing remote files are overwritten.
class BulkPushDialog extends StatefulWidget {
  final List<Host> hosts;
  final BulkActionService? serviceOverride; // tests
  const BulkPushDialog({super.key, required this.hosts, this.serviceOverride});

  @override
  State<BulkPushDialog> createState() => _BulkPushDialogState();
}

class _BulkPushDialogState extends State<BulkPushDialog> {
  late final BulkRunController _controller;
  final List<BulkPushSource> _sources = [];
  final _destController = TextEditingController(text: '/tmp');

  @override
  void initState() {
    super.initState();
    _controller =
        BulkRunController(service: _buildService(), hosts: widget.hosts)
          ..addListener(_onChanged);
  }

  BulkActionService _buildService() {
    if (widget.serviceOverride != null) return widget.serviceOverride!;
    final ssh = context.read<SshService>();
    final transfer = SftpTransferService(ssh);
    final ops = SftpFileOpsService(ssh);
    return BulkActionService(
      uploadFile: (host, local, remote, {onProgress}) =>
          transfer.uploadFile(host, local, remote, onProgress: onProgress),
      uploadDirectory: ({
        required host,
        required localDir,
        required remoteDir,
        required onProgress,
        required isCancelled,
      }) =>
          transfer.uploadDirectory(
            localDir: localDir,
            remoteHost: host,
            remoteDir: remoteDir,
            onProgress: onProgress,
            onFileSkipped: (_) {},
            isCancelled: isCancelled,
            overwrite: true,
          ),
      mkdir: ops.mkdir,
    );
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _destController.dispose();
    super.dispose();
  }

  Future<void> _addFiles() async {
    final files = await openFiles();
    if (files.isEmpty) return;
    final fresh = [
      for (final f in files)
        if (!_sources.any((s) => s.path == f.path)) f.path,
    ];
    try {
      final resolved = await BulkActionService.resolveSources(fresh);
      if (mounted) setState(() => _sources.addAll(resolved));
    } on FileSystemException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read source: ${e.message}')));
    }
  }

  Future<void> _addFolder() async {
    final dir = await getDirectoryPath();
    if (dir == null || _sources.any((s) => s.path == dir)) return;
    try {
      final resolved = await BulkActionService.resolveSources([dir]);
      if (mounted) setState(() => _sources.addAll(resolved));
    } on FileSystemException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read source: ${e.message}')));
    }
  }

  bool get _destValid => _destController.text.trim().startsWith('/');
  bool get _canPush =>
      _sources.isNotEmpty && _destValid && !_controller.isRunning;

  void _push() {
    if (!_canPush) return;
    _controller.pushFiles(List.of(_sources), _destController.text.trim());
  }

  Future<void> _close() async {
    if (_controller.isRunning) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Cancel push?',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
          content: const Text(
              'Transfers in flight will stop at the next file boundary.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep pushing')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Cancel push',
                    style: TextStyle(color: AppColors.red))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      _controller.cancel();
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final running = _controller.isRunning;
    final ok = _controller.countOf(BulkHostStatus.success);
    final failed = _controller.countOf(BulkHostStatus.failed);
    final cancelled = _controller.countOf(BulkHostStatus.cancelled);

    return PopScope(
      canPop: !_controller.isRunning,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Dialog(
        backgroundColor: AppColors.bg,
        insetPadding: const EdgeInsets.all(40),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 760,
            height: 600,
            child: Column(
              children: [
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(
                    color: AppColors.sidebar,
                    border:
                        Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.upload_file,
                          size: 15, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Text('Push files to ${widget.hosts.length} hosts',
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close,
                            size: 16, color: AppColors.textSecondary),
                        onPressed: _close,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: running ? null : _addFiles,
                            icon: const Icon(Icons.insert_drive_file_outlined,
                                size: 14),
                            label: const Text('ADD FILES',
                                style: TextStyle(fontSize: 11)),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: running ? null : _addFolder,
                            icon:
                                const Icon(Icons.folder_outlined, size: 14),
                            label: const Text('ADD FOLDER',
                                style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                      if (_sources.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 120),
                          child: SingleChildScrollView(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final s in _sources)
                                  Chip(
                                    backgroundColor: AppColors.card,
                                    side: const BorderSide(
                                        color: AppColors.border),
                                    label: Text(
                                        '${s.isDirectory ? '📁 ' : ''}${s.name} · ${formatByteSize(s.bytes)}',
                                        style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 11)),
                                    deleteIcon:
                                        const Icon(Icons.close, size: 12),
                                    onDeleted: running
                                        ? null
                                        : () =>
                                            setState(() => _sources.remove(s)),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Text('Destination',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              key: const Key('bulk-dest-field'),
                              controller: _destController,
                              enabled: !running,
                              onChanged: (_) => setState(() {}),
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontFamily: 'monospace'),
                              decoration: InputDecoration(
                                hintText: '/absolute/remote/path',
                                hintStyle: const TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 12),
                                errorText: _destValid
                                    ? null
                                    : 'Must be an absolute path',
                                isDense: true,
                                filled: true,
                                fillColor: AppColors.card,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: AppColors.border),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  running ? AppColors.red : AppColors.accent,
                              foregroundColor: Colors.black,
                            ),
                            onPressed: running
                                ? _controller.cancel
                                : (_canPush ? _push : null),
                            child: Text(running ? 'CANCEL' : 'PUSH',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text('Existing remote files will be overwritten.',
                          style: TextStyle(
                              color: AppColors.orange, fontSize: 11)),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                Expanded(
                    child:
                        BulkHostStatusList(results: _controller.results)),
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(
                    color: AppColors.sidebar,
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      if (_controller.hasRun)
                        Text(
                            '$ok ok · $failed failed${cancelled > 0 ? ' · $cancelled cancelled' : ''}',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 11)),
                      const Spacer(),
                      TextButton(
                        onPressed: _close,
                        child: const Text('CLOSE',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
