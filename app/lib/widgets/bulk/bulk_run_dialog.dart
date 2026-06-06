import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';

import '../../models/bulk_result.dart';
import '../../models/host.dart';
import '../../services/bulk_action_service.dart';
import '../../services/ssh_service.dart';
import '../../theme/app_theme.dart';
import 'bulk_diff_view.dart';
import 'bulk_host_status_list.dart';
import 'bulk_run_controller.dart';

/// Modal that runs one command (free text or snippet) on N hosts in
/// parallel; Results tab = per-host rows, Diff tab = output grouping.
class BulkRunDialog extends StatefulWidget {
  final List<Host> hosts;

  /// Tests inject a service with fake exec; production builds one over
  /// [SshService.exec] read from the tree.
  final BulkActionService? serviceOverride;

  const BulkRunDialog({super.key, required this.hosts, this.serviceOverride});

  @override
  State<BulkRunDialog> createState() => _BulkRunDialogState();
}

class _BulkRunDialogState extends State<BulkRunDialog> {
  late final BulkRunController _controller;
  final _commandController = TextEditingController();
  bool _showDiff = false;

  @override
  void initState() {
    super.initState();
    final service = widget.serviceOverride ??
        BulkActionService(exec: context.read<SshService>().exec);
    _controller = BulkRunController(service: service, hosts: widget.hosts)
      ..addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _commandController.dispose();
    super.dispose();
  }

  void _run() {
    final cmd = _commandController.text.trim();
    if (cmd.isEmpty || _controller.isRunning) return;
    setState(() => _showDiff = false);
    _controller.runCommand(cmd);
  }

  Future<void> _close() async {
    if (_controller.isRunning) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Cancel run?',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
          content: const Text(
              'Hosts still in flight will finish; queued hosts will be cancelled.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep running')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Cancel run',
                    style: TextStyle(color: AppColors.red))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      _controller.cancel();
    }
    if (mounted) Navigator.of(context).pop();
  }

  String get _summary {
    final ok = _controller.countOf(BulkHostStatus.success);
    final failed = _controller.countOf(BulkHostStatus.failed);
    final cancelled = _controller.countOf(BulkHostStatus.cancelled);
    var s = '$ok ok · $failed failed';
    if (cancelled > 0) s += ' · $cancelled cancelled';
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final snippets = context.watch<SnippetProvider>().snippets;
    final running = _controller.isRunning;
    final diffReady = _controller.hasRun && !running;

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
            width: 900,
            height: 650,
            child: Column(
              children: [
                // Header
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
                      const Icon(Icons.terminal,
                          size: 15, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Text('Run command on ${widget.hosts.length} hosts',
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
                // Command row
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('bulk-command-field'),
                          controller: _commandController,
                          onSubmitted: (_) => _run(),
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontFamily: 'monospace'),
                          decoration: InputDecoration(
                            hintText: 'Command to run on every host…',
                            hintStyle: const TextStyle(
                                color: AppColors.textTertiary, fontSize: 13),
                            isDense: true,
                            filled: true,
                            fillColor: AppColors.card,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: AppColors.border),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<Snippet>(
                        tooltip: 'Insert snippet',
                        color: AppColors.card,
                        icon: const Icon(Icons.data_object,
                            size: 18, color: AppColors.textSecondary),
                        itemBuilder: (_) => [
                          for (final s in snippets)
                            PopupMenuItem(
                              value: s,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 12)),
                                  Text(s.command,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: AppColors.textTertiary,
                                          fontSize: 10,
                                          fontFamily: 'monospace')),
                                ],
                              ),
                            ),
                        ],
                        onSelected: (s) =>
                            setState(() => _commandController.text = s.command),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              running ? AppColors.red : AppColors.accent,
                          foregroundColor: Colors.black,
                        ),
                        onPressed: running ? _controller.cancel : _run,
                        child: Text(running ? 'CANCEL' : 'RUN',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
                // Tabs
                Container(
                  decoration: const BoxDecoration(
                    border:
                        Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      _TabBtn(
                          label: 'RESULTS',
                          active: !_showDiff,
                          onTap: () => setState(() => _showDiff = false)),
                      _TabBtn(
                          label: 'DIFF',
                          active: _showDiff,
                          enabled: diffReady,
                          onTap: () => setState(() => _showDiff = true)),
                    ],
                  ),
                ),
                Expanded(
                  child: _showDiff
                      ? BulkDiffView(results: _controller.results)
                      : BulkHostStatusList(results: _controller.results),
                ),
                // Footer
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
                        Text(_summary,
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

class _TabBtn extends StatelessWidget {
  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;
  const _TabBtn(
      {required this.label,
      required this.active,
      this.enabled = true,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? AppColors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(label,
            style: TextStyle(
              color: !enabled
                  ? AppColors.textTertiary
                  : active
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            )),
      ),
    );
  }
}
