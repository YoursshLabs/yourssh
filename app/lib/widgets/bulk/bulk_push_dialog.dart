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
import '../../theme/app_theme.dart' show AppSnack;
import '../../util/bulk_format.dart';
import 'bulk_dialog_chrome.dart';
import 'bulk_host_status_list.dart';
import 'bulk_run_controller.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Modal that uploads local files/folders to the same remote path on N
/// hosts. Existing remote files are overwritten.
class BulkPushDialog extends StatefulWidget {
  final List<Host> hosts;
  final BulkActionService? serviceOverride; // tests
  final List<BulkPushSource> initialSources; // tests
  const BulkPushDialog({
    super.key,
    required this.hosts,
    this.serviceOverride,
    this.initialSources = const [],
  });

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
    _sources.addAll(widget.initialSources);
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
      AppSnack.error(context, 'Could not read source: ${e.message}');
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
      AppSnack.error(context, 'Could not read source: ${e.message}');
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
      final ok = await showYsDialog<bool>(
        context,
        builder: (ctx) => YsDialog(
          title: 'Cancel push?',
          body: Text('Transfers in flight will stop at the next file boundary.'),
          actions: [
            FButton(
              autofocus: true,
              variant: FButtonVariant.outline,
              onPress: () => Navigator.pop(ctx, false),
              child: const Text('Keep pushing'),
            ),
            FButton(
              variant: FButtonVariant.destructive,
              onPress: () => Navigator.pop(ctx, true),
              child: const Text('Cancel push'),
            ),
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
      child: YsDialogFrame(
        maxWidth: 760,
        padding: EdgeInsets.zero,
        child: BulkDialogBody(
          width: 760,
          height: 600,
          child: Column(
            children: [
              BulkDialogHeader(
                icon: FLucideIcons.upload,
                title: 'Push files to ${widget.hosts.length} hosts',
                onClose: _close,
              ),
              Padding(
                padding: const EdgeInsets.all(YsSpace.s3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: YsSpace.s2,
                      runSpacing: YsSpace.s2,
                      children: [
                        FButton(
                          variant: .outline,
                          size: .sm,
                          mainAxisSize: MainAxisSize.min,
                          onPress: running ? null : _addFiles,
                          prefix: const Icon(FLucideIcons.file),
                          child: const Text('ADD FILES'),
                        ),
                        FButton(
                          variant: .outline,
                          size: .sm,
                          mainAxisSize: MainAxisSize.min,
                          onPress: running ? null : _addFolder,
                          prefix: const Icon(FLucideIcons.folder),
                          child: const Text('ADD FOLDER'),
                        ),
                      ],
                    ),
                    if (_sources.isNotEmpty) ...[
                      const SizedBox(height: YsSpace.s2),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 120),
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final s in _sources)
                                _SourceChip(
                                  source: s,
                                  onRemove: running
                                      ? null
                                      : () => setState(() => _sources.remove(s)),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: YsSpace.s3 - 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: YsSpace.s2 + 2),
                          child: Text('Destination',
                              style: TextStyle(
                                  color: YsColors.mutedForeground,
                                  fontSize: 12)),
                        ),
                        const SizedBox(width: YsSpace.s2),
                        Expanded(
                          child: FTextField(
                            key: const Key('bulk-dest-field'),
                            control: FTextFieldControl.managed(
                              controller: _destController,
                              onChange: (_) => setState(() {}),
                            ),
                            enabled: !running,
                            autocorrect: false,
                            enableSuggestions: false,
                            hint: '/absolute/remote/path',
                            error: _destValid
                                ? null
                                : const Text('Must be an absolute path'),
                            style: .delta(
                              contentTextStyle: .delta([
                                .all(.delta(
                                  fontFamily: kYsMonoFontFamily,
                                  fontFamilyFallback: kYsMonoFontFallback,
                                )),
                              ]),
                            ),
                          ),
                        ),
                        const SizedBox(width: YsSpace.s2),
                        FButton(
                          variant: running ? .destructive : .primary,
                          mainAxisSize: MainAxisSize.min,
                          onPress: running
                              ? _controller.cancel
                              : (_canPush ? _push : null),
                          child: Text(running ? 'CANCEL' : 'PUSH'),
                        ),
                      ],
                    ),
                    const SizedBox(height: YsSpace.s2 - 2),
                    const Text('Existing remote files will be overwritten.',
                        style: TextStyle(color: YsColors.warn, fontSize: 11)),
                  ],
                ),
              ),
              const FDivider(),
              Expanded(child: BulkHostStatusList(results: _controller.results)),
              BulkDialogFooter(
                summary: _controller.hasRun
                    ? '$ok ok · $failed failed${cancelled > 0 ? ' · $cancelled cancelled' : ''}'
                    : null,
                onClose: _close,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A picked source: icon, `name · size` and a tooltipped remove button.
class _SourceChip extends StatelessWidget {
  final BulkPushSource source;
  final VoidCallback? onRemove;
  const _SourceChip({required this.source, required this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(left: YsSpace.s2 + 2),
    decoration: BoxDecoration(
      color: YsColors.secondary,
      borderRadius: BorderRadius.circular(YsRadius.control),
      border: Border.all(color: YsColors.border),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(source.isDirectory ? FLucideIcons.folder : FLucideIcons.file,
              size: 12, color: YsColors.mutedForeground),
          const SizedBox(width: YsSpace.s1 + 2),
          Flexible(
            child: Text(
              '${source.name} · ${formatByteSize(source.bytes)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: YsColors.foreground, fontSize: 11),
            ),
          ),
          Tooltip(
            message: 'Remove ${source.name}',
            excludeFromSemantics: true,
            child: FButton.icon(
              variant: .ghost,
              size: .xs,
              semanticsLabel: 'Remove ${source.name}',
              onPress: onRemove,
              child: const Icon(FLucideIcons.x),
            ),
          ),
        ],
      ),
    ),
  );
}
