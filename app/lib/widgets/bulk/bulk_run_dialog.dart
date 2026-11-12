import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';

import '../../models/bulk_result.dart';
import '../../models/host.dart';
import '../../services/bulk_action_service.dart';
import '../../services/ssh_service.dart';
import 'bulk_dialog_chrome.dart';
import 'bulk_diff_view.dart';
import 'bulk_host_status_list.dart';
import 'bulk_run_controller.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

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
    final service = widget.serviceOverride ?? _buildService();
    _controller = BulkRunController(service: service, hosts: widget.hosts)
      ..addListener(_onChanged);
  }

  BulkActionService _buildService() {
    final svc = context.read<SshService>();
    return BulkActionService(
        exec: (host, cmd) => svc.exec(host, cmd, auditSource: 'bulk'));
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
      final ok = await showYsDialog<bool>(
        context,
        builder: (ctx) => YsDialog(
          title: 'Cancel run?',
          body: Text(
            'Hosts still in flight will finish; queued hosts will be cancelled.',
          ),
          actions: [
            FButton(
              autofocus: true,
              variant: FButtonVariant.outline,
              onPress: () => Navigator.pop(ctx, false),
              child: const Text('Keep running'),
            ),
            FButton(
              variant: FButtonVariant.destructive,
              onPress: () => Navigator.pop(ctx, true),
              child: const Text('Cancel run'),
            ),
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
      child: YsDialogFrame(
        maxWidth: 900,
        padding: EdgeInsets.zero,
        child: BulkDialogBody(
          width: 900,
          height: 650,
          child: Column(
            children: [
              BulkDialogHeader(
                icon: FLucideIcons.squareTerminal,
                title: 'Run command on ${widget.hosts.length} hosts',
                onClose: _close,
              ),
              Padding(
                padding: const EdgeInsets.all(YsSpace.s3),
                child: Row(
                  children: [
                    Expanded(
                      child: FTextField(
                        key: const Key('bulk-command-field'),
                        control: FTextFieldControl.managed(
                            controller: _commandController),
                        onSubmit: (_) => _run(),
                        autocorrect: false,
                        enableSuggestions: false,
                        hint: 'Command to run on every host…',
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
                    _SnippetMenu(
                      snippets: snippets,
                      onSelected: (s) =>
                          setState(() => _commandController.text = s.command),
                    ),
                    const SizedBox(width: YsSpace.s2),
                    FButton(
                      variant: running ? .destructive : .primary,
                      mainAxisSize: MainAxisSize.min,
                      onPress: running ? _controller.cancel : _run,
                      child: Text(running ? 'CANCEL' : 'RUN'),
                    ),
                  ],
                ),
              ),
              FTabs(
                key: const Key('bulk-run-tabs'),
                control: .lifted(
                  index: _showDiff ? 1 : 0,
                  onChange: (i) {
                    // DIFF stays inert until a run has finished.
                    if (i == 1 && !diffReady) return;
                    setState(() => _showDiff = i == 1);
                  },
                ),
                children: [
                  FTabEntry(
                      label: const Text('RESULTS'),
                      child: const SizedBox.shrink()),
                  FTabEntry(
                      label: Text('DIFF',
                          style: diffReady
                              ? null
                              : const TextStyle(color: YsColors.off)),
                      child: const SizedBox.shrink()),
                ],
              ),
              const FDivider(),
              Expanded(
                child: _showDiff
                    ? BulkDiffView(results: _controller.results)
                    : BulkHostStatusList(results: _controller.results),
              ),
              BulkDialogFooter(
                summary: _controller.hasRun ? _summary : null,
                onClose: _close,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icon button opening the saved snippets; picking one fills the command.
class _SnippetMenu extends StatelessWidget {
  final List<Snippet> snippets;
  final ValueChanged<Snippet> onSelected;
  const _SnippetMenu({required this.snippets, required this.onSelected});

  @override
  Widget build(BuildContext context) => FPopoverMenu(
    menuAnchor: Alignment.topRight,
    childAnchor: Alignment.bottomRight,
    menuBuilder: (context, controller, _) => [
      FItemGroup(
        children: [
          for (final s in snippets)
            FItem(
              title: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                s.command,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: kYsMonoFontFamily,
                  fontFamilyFallback: kYsMonoFontFallback,
                ),
              ),
              onPress: () {
                controller.hide();
                onSelected(s);
              },
            ),
        ],
      ),
    ],
    builder: (context, controller, _) => Tooltip(
      message: snippets.isEmpty ? 'No snippets saved' : 'Insert snippet',
      excludeFromSemantics: true,
      child: FButton.icon(
        variant: .outline,
        semanticsLabel: 'Insert snippet',
        // Nothing to pick from: the old empty popup is just inert here.
        onPress: snippets.isEmpty ? null : controller.toggle,
        child: const Icon(FLucideIcons.braces),
      ),
    ),
  );
}
