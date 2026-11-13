import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../models/container_entry.dart';
import '../models/host.dart';
import '../services/container_service.dart';
import '../theme/app_theme.dart';
import 'container_widgets.dart';
import 'ys_form_controls.dart';

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

  // Generation counter for _selectStack to cancel stale fetches.
  int _servicesGen = 0;

  // Manual path input
  final TextEditingController _manualCtrl = TextEditingController();
  bool _showManualInput = false;

  // Stacks added by absolute path; kept across discovery refreshes (discovery
  // only scans a fixed set of roots, so these would otherwise vanish).
  final List<ComposeStack> _manualStacks = [];

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

  void _showError(Object e) {
    if (!mounted) return;
    final s = e.toString();
    final msg = s.length > 200 ? '${s.substring(0, 200)}…' : s;
    AppSnack.error(context, msg);
  }

  Future<void> _loadStacks() async {
    setState(() {
      _loadingStacks = true;
      _stacksError = null;
    });
    try {
      final discovered = await widget.service.discoverComposeStacks(widget.host);
      _stacks = [
        ...discovered,
        ..._manualStacks
            .where((m) => !discovered.any((d) => d.projectDir == m.projectDir)),
      ];
    } catch (e) {
      _stacksError = e.toString();
    } finally {
      if (mounted) setState(() => _loadingStacks = false);
    }
  }

  Future<void> _selectStack(ComposeStack stack) async {
    _closeLogs();
    // Invalidate any in-flight service fetch up front, including on the collapse
    // path, so a stale result can't repopulate _services after deselection.
    final gen = ++_servicesGen;
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
      if (mounted && gen == _servicesGen) setState(() => _services = svcs);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted && gen == _servicesGen) setState(() => _loadingServices = false);
    }
  }

  /// `docker compose down` removes containers and networks, so it asks first;
  /// Cancel holds default focus.
  Future<void> _confirmDown(ComposeStack stack, String key) async {
    final ok = await showYsConfirm(
      context,
      title: 'Bring the stack down?',
      message:
          'docker compose down stops and removes the containers and networks of ${stack.name}. Named volumes are kept.',
      confirmLabel: 'Down',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _stackAction(
        stack, key, () => widget.service.composeDown(widget.host, stack));
  }

  Future<void> _stackAction(
      ComposeStack stack, String key, Future<void> Function() action) async {
    setState(() => _actionLoading[key] = true);
    try {
      await action();
      if (!mounted) return;
      await _loadStacks();
      if (!mounted) return;
      // If the previously selected stack is gone, clear selection.
      if (_selectedStack != null &&
          !_stacks.any((s) => s.projectDir == _selectedStack!.projectDir)) {
        setState(() {
          _selectedStack = null;
          _services = [];
        });
        _closeLogs();
      } else if (_selectedStack?.projectDir == stack.projectDir) {
        final gen = _servicesGen;
        final svcs = await widget.service.listComposeServices(widget.host, stack);
        if (mounted && gen == _servicesGen) setState(() => _services = svcs);
      }
    } catch (e) {
      _showError(e);
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
      _logService = null;
      _logLines.clear();
    });
  }

  Future<void> _addManualPath() async {
    final path = _manualCtrl.text.trim();
    if (path.isEmpty) return;
    final stack = ContainerService.composeStackFromPath(path);
    if (stack == null) {
      _showError('Enter an absolute path to a compose file');
      return;
    }
    setState(() => _actionLoading['manual'] = true);
    try {
      await widget.service.validateComposeFile(widget.host, path);
      if (!mounted) return;
      setState(() {
        if (!_manualStacks.any((s) => s.projectDir == stack.projectDir)) {
          _manualStacks.add(stack);
        }
        if (!_stacks.any((s) => s.projectDir == stack.projectDir)) {
          _stacks = [..._stacks, stack];
        }
        _showManualInput = false;
        _manualCtrl.clear();
      });
    } catch (e) {
      _showError(e);
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
        padding: const EdgeInsets.only(bottom: YsSpace.s1),
        child: Row(children: [
          const Expanded(
            child: Text('Compose Stacks',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 12, color: YsColors.mutedForeground)),
          ),
          ContainerIconAction(
            icon: FLucideIcons.plus,
            tooltip: 'Add path manually',
            onPress: () =>
                setState(() => _showManualInput = !_showManualInput),
          ),
          ContainerIconAction(
            icon: FLucideIcons.refreshCw,
            tooltip: 'Refresh',
            onPress: _loadStacks,
          ),
        ]),
      ),
      // Manual path input
      if (_showManualInput)
        Padding(
          padding: const EdgeInsets.only(bottom: YsSpace.s2),
          child: Row(children: [
            Expanded(
              child: FTextField(
                control: .managed(controller: _manualCtrl),
                hint: '/path/to/docker-compose.yml',
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmit: (_) => _addManualPath(),
              ),
            ),
            const SizedBox(width: YsSpace.s2),
            FButton(
              mainAxisSize: MainAxisSize.min,
              onPress: _actionLoading['manual'] == true ? null : _addManualPath,
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
        const FDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: YsSpace.s1),
          child: Row(children: [
            Expanded(
              child: Text('Services in ${_selectedStack!.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, color: YsColors.mutedForeground)),
            ),
          ]),
        ),
        Expanded(
          flex: 1,
          child: _loadingServices
              ? const Center(child: FCircularProgress())
              : _buildServiceList(),
        ),
      ],
      // Log panel
      if (hasLogs) ...[
        const FDivider(),
        Expanded(
          flex: 2,
          child: ContainerLogPanel(
            title: 'Logs: ${_logService!.name}',
            lines: _logLines,
            controller: _logScroll,
            onClear: () => setState(() => _logLines.clear()),
            onClose: _closeLogs,
          ),
        ),
      ],
    ]);
  }

  Widget _buildStackList() {
    if (_loadingStacks) return const Center(child: FCircularProgress());
    if (_stacksError != null) {
      return Center(child: Text(_stacksError!, textAlign: TextAlign.center));
    }
    if (_stacks.isEmpty) {
      return const YsEmptyState(
        icon: FLucideIcons.folderOpen,
        title: 'No Compose stacks found.',
        message: 'Tap + to add a path manually.',
      );
    }
    return ListView.builder(
      itemCount: _stacks.length,
      itemBuilder: (_, i) => _stackTile(_stacks[i]),
    );
  }

  Widget _stackTile(ComposeStack stack) {
    final selected = _selectedStack?.projectDir == stack.projectDir;
    final upKey = 'up_${stack.projectDir}';
    final downKey = 'down_${stack.projectDir}';
    return Padding(
      padding: const EdgeInsets.only(bottom: YsSpace.s1),
      child: settingsTileGroup(children: [
        FTile.raw(
          key: ValueKey('stack-${stack.projectDir}'),
          selected: selected,
          onPress: () => _selectStack(stack),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(stack.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: YsColors.foreground)),
                  Text('${stack.status}  •  ${stack.projectDir}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: YsColors.mutedForeground)),
                ],
              ),
            ),
            const SizedBox(width: YsSpace.s2),
            if (_actionLoading[upKey] == true)
              const ContainerSpinner()
            else
              ContainerTextAction(
                label: 'Up',
                onPress: () => _stackAction(stack, upKey,
                    () => widget.service.composeUp(widget.host, stack)),
              ),
            if (_actionLoading[downKey] == true)
              const ContainerSpinner()
            else
              ContainerTextAction(
                label: 'Down',
                onPress: () => _confirmDown(stack, downKey),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildServiceList() {
    if (_services.isEmpty) {
      return const Center(child: Text('No services found.'));
    }
    return ListView.builder(
      itemCount: _services.length,
      itemBuilder: (_, i) => _serviceTile(_services[i]),
    );
  }

  Widget _serviceTile(ComposeService svc) {
    final stack = _selectedStack!;
    // 'degraded' = some replicas up — still offer Stop, not Start.
    final running = svc.status == 'running' || svc.status == 'degraded';
    final startKey = 'svcstart_${stack.projectDir}_${svc.name}';
    final stopKey = 'svcstop_${stack.projectDir}_${svc.name}';
    final isLogTarget = _logService?.name == svc.name;

    return ContainerRow(
      key: ValueKey('service-${svc.name}'),
      title: svc.name,
      subtitle:
          '${svc.status}  •  ${svc.image}  •  ${svc.replicas} replica${svc.replicas == 1 ? '' : 's'}',
      highlighted: isLogTarget,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (running && _actionLoading[stopKey] != true)
          ContainerIconAction(
            icon: FLucideIcons.circleStop,
            tooltip: 'Stop service',
            onPress: () => _stackAction(
                stack,
                stopKey,
                () => widget.service
                    .stopComposeService(widget.host, stack, svc.name)),
          ),
        if (!running && _actionLoading[startKey] != true)
          ContainerIconAction(
            icon: FLucideIcons.circlePlay,
            tooltip: 'Start service',
            onPress: () => _stackAction(
                stack,
                startKey,
                () => widget.service
                    .startComposeService(widget.host, stack, svc.name)),
          ),
        ContainerIconAction(
          icon: FLucideIcons.fileText,
          tooltip: 'Logs',
          active: isLogTarget,
          onPress: () => isLogTarget ? _closeLogs() : _openServiceLogs(svc),
        ),
      ]),
    );
  }
}
