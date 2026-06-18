import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/container_entry.dart';
import '../models/host.dart';
import '../providers/session_provider.dart';
import '../services/container_service.dart';
import '../theme/app_theme.dart';

class DockerPanel extends StatefulWidget {
  const DockerPanel({super.key, required this.host, required this.service});

  final Host host;
  final ContainerService service;

  @override
  State<DockerPanel> createState() => _DockerPanelState();
}

class _DockerPanelState extends State<DockerPanel> {
  List<ContainerEntry> _containers = [];
  bool _loading = false;
  String? _error;

  // Log panel state
  ContainerEntry? _logContainer;
  StreamSubscription<String>? _logSub;
  final List<String> _logLines = [];
  final ScrollController _logScroll = ScrollController();
  bool _autoScroll = true;

  // Per-container action loading
  final Map<String, bool> _actionLoading = {};

  @override
  void initState() {
    super.initState();
    _logScroll.addListener(_onLogScroll);
    _refresh();
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _logScroll.dispose();
    super.dispose();
  }

  void _onLogScroll() {
    final pos = _logScroll.position;
    _autoScroll = pos.pixels >= pos.maxScrollExtent - 8;
  }

  void _scrollToBottom() {
    if (!_autoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await widget.service.listDockerContainers(widget.host);
      if (mounted) setState(() { _containers = result; _error = null; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  bool _isRunning(ContainerEntry c) =>
      c.status.toLowerCase().startsWith('up');

  Future<void> _runAction(ContainerEntry c, Future<void> Function() action) async {
    setState(() => _actionLoading[c.id] = true);
    try {
      await action();
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade800),
        );
      }
    } finally {
      if (mounted) setState(() => _actionLoading.remove(c.id));
    }
  }

  void _openLogs(ContainerEntry c) {
    _logSub?.cancel();
    setState(() {
      _logContainer = c;
      _logLines.clear();
      _autoScroll = true;
    });
    _logSub = widget.service
        .streamDockerLogs(widget.host, c.id)
        .listen((line) {
      if (mounted) {
        setState(() {
          _logLines.add(line);
          if (_logLines.length > 2000) {
            _logLines.removeRange(0, _logLines.length - 2000);
          }
        });
        _scrollToBottom();
      }
    }, onDone: () {
      if (mounted) {
        setState(() => _logLines.add('— connection closed —'));
        _scrollToBottom();
      }
    }, onError: (e) {
      if (mounted) {
        setState(() => _logLines.add('— error: $e —'));
        _scrollToBottom();
      }
    });
  }

  void _closeLogs() {
    _logSub?.cancel();
    _logSub = null;
    setState(() {
      _logContainer = null;
      _logLines.clear();
    });
  }

  Future<void> _execContainer(ContainerEntry c) async {
    final sessionProvider = context.read<SessionProvider>();
    await sessionProvider.connect(
      widget.host,
      initialCommand: ContainerService.dockerExecCommand(c.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 36, color: AppColors.textTertiary),
          const SizedBox(height: 8),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: _refresh, child: const Text('Retry')),
        ]),
      );
    }
    if (_containers.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.inbox, size: 36, color: AppColors.textTertiary),
          const SizedBox(height: 8),
          const Text('No containers found.'),
          const SizedBox(height: 12),
          FilledButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
              onPressed: _refresh),
        ]),
      );
    }

    final hasLogs = _logContainer != null;
    return Column(
      children: [
        // Header row
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
          child: Row(
            children: [
              Text('${_containers.length} container${_containers.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh, size: 16),
                onPressed: _refresh,
              ),
            ],
          ),
        ),
        // Container list
        Expanded(
          flex: hasLogs ? 1 : 2,
          child: ListView.separated(
            itemCount: _containers.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: AppColors.border),
            itemBuilder: (_, i) => _containerTile(_containers[i]),
          ),
        ),
        // Log panel
        if (hasLogs) ...[
          const Divider(height: 1, color: AppColors.border),
          _logPanel(),
        ],
      ],
    );
  }

  Widget _containerTile(ContainerEntry c) {
    final running = _isRunning(c);
    final loading = _actionLoading[c.id] == true;
    final isLogTarget = _logContainer?.id == c.id;

    return Container(
      decoration: isLogTarget
          ? BoxDecoration(
              border: Border(
                left: BorderSide(color: AppColors.accent, width: 3),
              ),
            )
          : null,
      child: ListTile(
        dense: true,
        title: Text(c.name,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        subtitle: Text('${c.image}  •  ${c.status}',
            style:
                const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        trailing: loading
            ? const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : _actionButtons(c, running),
      ),
    );
  }

  Widget _actionButtons(ContainerEntry c, bool running) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (running)
        _iconBtn(Icons.stop_circle_outlined, 'Stop',
            () => _runAction(c, () => widget.service.stopContainer(widget.host, c.id))),
      if (running)
        _iconBtn(Icons.replay, 'Restart',
            () => _runAction(c, () => widget.service.restartContainer(widget.host, c.id))),
      if (!running)
        _iconBtn(Icons.play_circle_outline, 'Start',
            () => _runAction(c, () => widget.service.startContainer(widget.host, c.id))),
      _iconBtn(Icons.terminal, 'Exec', () => _execContainer(c)),
      if (running)
        _iconBtn(
          Icons.article_outlined,
          'Logs',
          () => _logContainer?.id == c.id ? _closeLogs() : _openLogs(c),
          active: _logContainer?.id == c.id,
        ),
    ]);
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onTap,
      {bool active = false}) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 16),
      color: active ? AppColors.accent : null,
      onPressed: onTap,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      padding: EdgeInsets.zero,
    );
  }

  Widget _logPanel() {
    return Expanded(
      flex: 2,
      child: Column(
        children: [
          // Log panel header
          Container(
            color: AppColors.card,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(children: [
              const Icon(Icons.article_outlined, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Logs: ${_logContainer!.name}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis),
              ),
              TextButton(
                onPressed: () => setState(() => _logLines.clear()),
                child: const Text('Clear', style: TextStyle(fontSize: 11)),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 14),
                onPressed: _closeLogs,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
              ),
            ]),
          ),
          // Log lines
          Expanded(
            child: ListView.builder(
              controller: _logScroll,
              padding: const EdgeInsets.all(8),
              itemCount: _logLines.length,
              itemBuilder: (_, i) => Text(
                _logLines[i],
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: AppColors.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
