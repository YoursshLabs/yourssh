import 'dart:async';

import 'package:flutter/material.dart';

import '../models/container_entry.dart';
import '../models/host.dart';
import '../services/container_service.dart';
import '../theme/app_theme.dart';

class ComposePanel extends StatefulWidget {
  const ComposePanel({super.key, required this.host, required this.service});

  final Host host;
  final ContainerService service;

  @override
  State<ComposePanel> createState() => _ComposePanelState();
}

class _ComposePanelState extends State<ComposePanel> {
  List<ComposeStack> _stacks = [];
  bool _loadingStacks = false;
  String? _stacksError;

  ComposeStack? _selectedStack;
  List<ComposeService> _services = [];
  bool _loadingServices = false;

  // Log panel
  ComposeService? _logService;
  StreamSubscription<String>? _logSub;
  final List<String> _logLines = [];
  final ScrollController _logScroll = ScrollController();
  bool _autoScroll = true;

  // Per-action loading
  final Map<String, bool> _actionLoading = {};

  // Manual path input
  final TextEditingController _manualCtrl = TextEditingController();
  bool _showManualInput = false;

  @override
  void initState() {
    super.initState();
    _logScroll.addListener(() {
      final pos = _logScroll.position;
      _autoScroll = pos.pixels >= pos.maxScrollExtent - 8;
    });
    _loadStacks();
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _logScroll.dispose();
    _manualCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_autoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _loadStacks() async {
    setState(() {
      _loadingStacks = true;
      _stacksError = null;
    });
    try {
      _stacks = await widget.service.discoverComposeStacks(widget.host);
    } catch (e) {
      _stacksError = e.toString();
    } finally {
      if (mounted) setState(() => _loadingStacks = false);
    }
  }

  Future<void> _selectStack(ComposeStack stack) async {
    if (_selectedStack?.projectDir == stack.projectDir) {
      setState(() {
        _selectedStack = null;
        _services = [];
      });
      return;
    }
    setState(() {
      _selectedStack = stack;
      _services = [];
      _loadingServices = true;
    });
    try {
      final svcs = await widget.service.listComposeServices(widget.host, stack);
      if (mounted) setState(() => _services = svcs);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade800),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingServices = false);
    }
  }

  Future<void> _stackAction(
      ComposeStack stack, String key, Future<void> Function() action) async {
    setState(() => _actionLoading[key] = true);
    try {
      await action();
      await _loadStacks();
      if (_selectedStack?.projectDir == stack.projectDir) {
        final svcs = await widget.service.listComposeServices(widget.host, stack);
        if (mounted) setState(() => _services = svcs);
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().length > 200
            ? '${e.toString().substring(0, 200)}…'
            : e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800),
        );
      }
    } finally {
      if (mounted) setState(() => _actionLoading.remove(key));
    }
  }

  void _openServiceLogs(ComposeService svc) {
    final stack = _selectedStack;
    if (stack == null) return;
    _logSub?.cancel();
    setState(() {
      _logService = svc;
      _logLines.clear();
      _autoScroll = true;
    });
    _logSub = widget.service
        .streamComposeServiceLogs(widget.host, stack, svc.name)
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
      if (mounted) setState(() => _logLines.add('— connection closed —'));
    }, onError: (e) {
      if (mounted) setState(() => _logLines.add('— error: $e —'));
    });
  }

  void _closeLogs() {
    _logSub?.cancel();
    _logSub = null;
    setState(() {
      _logService = null;
      _logLines.clear();
    });
  }

  Future<void> _addManualPath() async {
    final path = _manualCtrl.text.trim();
    if (path.isEmpty) return;
    setState(() => _actionLoading['manual'] = true);
    try {
      final r = await widget.service.ssh.exec(
          widget.host,
          "docker compose -f '$path' config --services 2>&1",
          auditSource: 'devops');
      if (r.exitCode != 0) throw Exception('Not a valid Compose file: $path');
      final dir = path.contains('/')
          ? path.substring(0, path.lastIndexOf('/'))
          : '.';
      final name = dir.substring(dir.lastIndexOf('/') + 1);
      final stack = ComposeStack(name: name, projectDir: dir, status: 'unknown');
      setState(() {
        if (!_stacks.any((s) => s.projectDir == dir)) {
          _stacks = [..._stacks, stack];
        }
        _showManualInput = false;
        _manualCtrl.clear();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red.shade800),
        );
      }
    } finally {
      if (mounted) setState(() => _actionLoading.remove('manual'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLogs = _logService != null;
    return Column(children: [
      // Toolbar
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
        child: Row(children: [
          const Text('Compose Stacks',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const Spacer(),
          IconButton(
            tooltip: 'Add path manually',
            icon: const Icon(Icons.add, size: 16),
            onPressed: () =>
                setState(() => _showManualInput = !_showManualInput),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 16),
            onPressed: _loadStacks,
          ),
        ]),
      ),
      // Manual path input
      if (_showManualInput)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _manualCtrl,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  hintText: '/path/to/docker-compose.yml',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _addManualPath(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _actionLoading['manual'] == true ? null : _addManualPath,
              child: const Text('Add'),
            ),
          ]),
        ),
      // Stack list
      Expanded(
        flex: _selectedStack != null ? 1 : 3,
        child: _buildStackList(),
      ),
      // Service list
      if (_selectedStack != null) ...[
        const Divider(height: 1, color: AppColors.border),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Text('Services in ${_selectedStack!.name}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
          ]),
        ),
        Expanded(
          flex: 1,
          child: _loadingServices
              ? const Center(child: CircularProgressIndicator())
              : _buildServiceList(),
        ),
      ],
      // Log panel
      if (hasLogs) ...[
        const Divider(height: 1, color: AppColors.border),
        _buildLogPanel(),
      ],
    ]);
  }

  Widget _buildStackList() {
    if (_loadingStacks) return const Center(child: CircularProgressIndicator());
    if (_stacksError != null) {
      return Center(child: Text(_stacksError!, textAlign: TextAlign.center));
    }
    if (_stacks.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.folder_open, size: 36, color: AppColors.textTertiary),
          const SizedBox(height: 8),
          const Text('No Compose stacks found.'),
          const SizedBox(height: 4),
          const Text('Tap + to add a path manually.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ]),
      );
    }
    return ListView.separated(
      itemCount: _stacks.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (_, i) => _stackTile(_stacks[i]),
    );
  }

  Widget _stackTile(ComposeStack stack) {
    final selected = _selectedStack?.projectDir == stack.projectDir;
    final upKey = 'up_${stack.projectDir}';
    final downKey = 'down_${stack.projectDir}';
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: AppColors.accent.withValues(alpha: 0.08),
      title: Text(stack.name,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text('${stack.status}  •  ${stack.projectDir}',
          style:
              const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          overflow: TextOverflow.ellipsis),
      onTap: () => _selectStack(stack),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (_actionLoading[upKey] == true)
          const SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        else
          TextButton(
            onPressed: () => _stackAction(
                stack, upKey, () => widget.service.composeUp(widget.host, stack)),
            child: const Text('Up', style: TextStyle(fontSize: 12)),
          ),
        if (_actionLoading[downKey] == true)
          const SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        else
          TextButton(
            onPressed: () => _stackAction(
                stack, downKey, () => widget.service.composeDown(widget.host, stack)),
            child: const Text('Down', style: TextStyle(fontSize: 12)),
          ),
      ]),
    );
  }

  Widget _buildServiceList() {
    if (_services.isEmpty) {
      return const Center(child: Text('No services found.'));
    }
    return ListView.separated(
      itemCount: _services.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (_, i) => _serviceTile(_services[i]),
    );
  }

  Widget _serviceTile(ComposeService svc) {
    final stack = _selectedStack!;
    final running = svc.status == 'running';
    final startKey = 'svcstart_${stack.projectDir}_${svc.name}';
    final stopKey = 'svcstop_${stack.projectDir}_${svc.name}';
    final isLogTarget = _logService?.name == svc.name;

    return ListTile(
      dense: true,
      title: Text(svc.name,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text(
          '${svc.status}  •  ${svc.image}  •  ${svc.replicas} replica${svc.replicas == 1 ? '' : 's'}',
          style:
              const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (running && _actionLoading[stopKey] != true)
          IconButton(
            tooltip: 'Stop service',
            icon: const Icon(Icons.stop_circle_outlined, size: 16),
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => _stackAction(
                stack, stopKey,
                () => widget.service.stopComposeService(widget.host, stack, svc.name)),
          ),
        if (!running && _actionLoading[startKey] != true)
          IconButton(
            tooltip: 'Start service',
            icon: const Icon(Icons.play_circle_outline, size: 16),
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => _stackAction(
                stack, startKey,
                () => widget.service.startComposeService(widget.host, stack, svc.name)),
          ),
        IconButton(
          tooltip: 'Logs',
          icon: const Icon(Icons.article_outlined, size: 16),
          color: isLogTarget ? AppColors.accent : null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: () =>
              isLogTarget ? _closeLogs() : _openServiceLogs(svc),
        ),
      ]),
    );
  }

  Widget _buildLogPanel() {
    return Expanded(
      flex: 2,
      child: Column(children: [
        Container(
          color: AppColors.card,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            const Icon(Icons.article_outlined,
                size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Logs: ${_logService!.name}',
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
              constraints:
                  const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            controller: _logScroll,
            padding: const EdgeInsets.all(8),
            itemCount: _logLines.length,
            itemBuilder: (_, i) => Text(_logLines[i],
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: AppColors.textPrimary)),
          ),
        ),
      ]),
    );
  }
}
