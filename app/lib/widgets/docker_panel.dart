import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../models/container_entry.dart';
import '../models/host.dart';
import '../providers/session_provider.dart';
import '../services/container_service.dart';
import '../theme/app_theme.dart';
import 'container_widgets.dart';

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

  /// [silent] skips the full-screen loading state — used for the refresh that
  /// follows a lifecycle action so the list (and any open log panel) isn't torn
  /// down and replaced by a spinner on every Stop/Start/Restart.
  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _error = null; });
    try {
      final result = await widget.service.listDockerContainers(widget.host);
      if (mounted) {
        setState(() {
          _containers = result;
          _error = null;
          if (!silent) _loading = false;
          // Close log panel if the logged container is no longer in the list.
          if (_logContainer != null &&
              !result.any((c) => c.id == _logContainer!.id)) {
            _logSub?.cancel();
            _logSub = null;
            _logContainer = null;
            _logLines.clear();
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); if (!silent) _loading = false; });
    }
  }

  bool _isRunning(ContainerEntry c) {
    final s = c.status.toLowerCase();
    // `Up …` (incl. `Up … (Paused)`) and `Restarting …` are live containers —
    // they get Stop/Restart, not Start.
    return s.startsWith('up') || s.startsWith('restarting');
  }

  Future<void> _runAction(ContainerEntry c, Future<void> Function() action) async {
    setState(() => _actionLoading[c.id] = true);
    try {
      await action();
      if (!mounted) return;
      await _refresh(silent: true);
    } catch (e) {
      if (mounted) AppSnack.error(context, e.toString());
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
    if (!mounted) return;
    final sessionProvider = context.read<SessionProvider>();
    try {
      await sessionProvider.connect(
        widget.host,
        initialCommand: ContainerService.dockerExecCommand(c.id),
      );
    } catch (e) {
      if (mounted) AppSnack.error(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: FCircularProgress());
    if (_error != null) {
      return YsEmptyState(
        icon: FLucideIcons.circleAlert,
        title: _error!,
        action: FButton(onPress: _refresh, child: const Text('Retry')),
      );
    }
    if (_containers.isEmpty) {
      return YsEmptyState(
        icon: FLucideIcons.inbox,
        title: 'No containers found.',
        action: FButton(
          prefix: const Icon(FLucideIcons.refreshCw),
          onPress: _refresh,
          child: const Text('Refresh'),
        ),
      );
    }

    final hasLogs = _logContainer != null;
    return Column(
      children: [
        // Header row
        Padding(
          padding: const EdgeInsets.only(bottom: YsSpace.s1),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_containers.length} container${_containers.length == 1 ? '' : 's'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: YsColors.mutedForeground,
                    fontSize: 12,
                  ),
                ),
              ),
              ContainerIconAction(
                icon: FLucideIcons.refreshCw,
                tooltip: 'Refresh',
                onPress: _refresh,
              ),
            ],
          ),
        ),
        // Container list
        Expanded(
          flex: hasLogs ? 1 : 2,
          child: ListView.builder(
            itemCount: _containers.length,
            itemBuilder: (_, i) => _containerTile(_containers[i]),
          ),
        ),
        // Log panel
        if (hasLogs) ...[
          const FDivider(),
          Expanded(
            flex: 2,
            child: ContainerLogPanel(
              title: 'Logs: ${_logContainer!.name}',
              lines: _logLines,
              controller: _logScroll,
              onClear: () => setState(() => _logLines.clear()),
              onClose: _closeLogs,
            ),
          ),
        ],
      ],
    );
  }

  Widget _containerTile(ContainerEntry c) {
    final running = _isRunning(c);
    final loading = _actionLoading[c.id] == true;
    return ContainerRow(
      key: ValueKey('container-${c.id}'),
      title: c.name,
      subtitle: '${c.image}  •  ${c.status}',
      highlighted: _logContainer?.id == c.id,
      trailing: loading
          ? const ContainerSpinner()
          : _actionButtons(c, running),
    );
  }

  Widget _actionButtons(ContainerEntry c, bool running) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (running)
        ContainerIconAction(
          icon: FLucideIcons.circleStop,
          tooltip: 'Stop',
          onPress: () => _runAction(
              c, () => widget.service.stopContainer(widget.host, c.id)),
        ),
      if (running)
        ContainerIconAction(
          icon: FLucideIcons.rotateCw,
          tooltip: 'Restart',
          onPress: () => _runAction(
              c, () => widget.service.restartContainer(widget.host, c.id)),
        ),
      if (!running)
        ContainerIconAction(
          icon: FLucideIcons.circlePlay,
          tooltip: 'Start',
          onPress: () => _runAction(
              c, () => widget.service.startContainer(widget.host, c.id)),
        ),
      ContainerIconAction(
        icon: FLucideIcons.terminal,
        tooltip: 'Exec',
        onPress: () => _execContainer(c),
      ),
      if (running)
        ContainerIconAction(
          icon: FLucideIcons.fileText,
          tooltip: 'Logs',
          active: _logContainer?.id == c.id,
          onPress: () =>
              _logContainer?.id == c.id ? _closeLogs() : _openLogs(c),
        ),
    ]);
  }
}
