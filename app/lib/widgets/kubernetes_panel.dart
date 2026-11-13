import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/container_entry.dart';
import '../models/host.dart';
import '../providers/session_provider.dart';
import '../services/container_service.dart';
import '../services/ssh_service.dart';
import '../theme/app_theme.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import 'container_widgets.dart';
import 'ys_form_controls.dart';

class KubernetesPanel extends StatefulWidget {
  const KubernetesPanel({
    super.key,
    required this.host,
    this.onOpenBrowser,
  });

  final Host host;

  /// If non-null, "Open in Browser" buttons are shown for active port-forwards.
  final void Function(String url)? onOpenBrowser;

  @override
  State<KubernetesPanel> createState() => _KubernetesPanelState();
}

class _KubernetesPanelState extends State<KubernetesPanel> {
  ContainerService? _svc;

  // ── Namespace / context ──────────────────────────────
  String _namespace = 'default';
  bool _allNamespaces = false;
  late TextEditingController _nsCtrl;

  String? _context;
  List<String> _contexts = [];

  // ── Pod list ─────────────────────────────────────────
  List<PodEntry> _pods = [];
  bool _loading = false;
  String? _error;

  // ── Log panel ────────────────────────────────────────
  PodEntry? _logPod;
  String? _logContainer;
  StreamSubscription<String>? _logSub;
  final List<String> _logLines = [];
  final ScrollController _logScroll = ScrollController();

  // ── Port forwards ────────────────────────────────────
  final List<K8sForwardHandle> _forwards = [];

  @override
  void initState() {
    super.initState();
    _nsCtrl = TextEditingController(text: _namespace);
    _loadContexts();
  }

  @override
  void didUpdateWidget(KubernetesPanel old) {
    super.didUpdateWidget(old);
    if (old.host.id != widget.host.id) {
      _context = null;
      _contexts = [];
      _pods = [];
      _error = null;
      _closeLogPanel();
      for (final f in _forwards) {
        f.stop();
      }
      _forwards.clear();
      _loadContexts();
    }
  }

  @override
  void dispose() {
    _nsCtrl.dispose();
    _logSub?.cancel();
    _logScroll.dispose();
    for (final f in _forwards) {
      f.stop();
    }
    super.dispose();
  }

  ContainerService _service() =>
      _svc ??= ContainerService(context.read<SshService>());

  Future<void> _loadContexts() async {
    final ctxs = await _service().listContexts(widget.host);
    if (mounted) setState(() => _contexts = ctxs);
  }

  Future<void> _refresh() async {
    _namespace =
        _nsCtrl.text.trim().isEmpty ? 'default' : _nsCtrl.text.trim();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _pods = await _service().listPods(
        widget.host,
        namespace: _namespace,
        allNamespaces: _allNamespaces,
        context: _context,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _headerRow(),
        if (_forwards.isNotEmpty) _activeForwardsBar(),
        Expanded(child: _body()),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _logPod != null ? _logPanel() : const SizedBox.shrink(),
        ),
      ],
    );
  }

  // ── Header ───────────────────────────────────────────

  Widget _headerRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: YsSpace.s2),
      child: Wrap(
        spacing: YsSpace.s3,
        runSpacing: YsSpace.s2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (_contexts.isNotEmpty) _contextDropdown(),
          SizedBox(
            width: 180,
            child: FTextField(
              key: const ValueKey('k8s-namespace'),
              enabled: !_allNamespaces,
              label: const Text('Namespace'),
              control: .managed(controller: _nsCtrl),
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onSubmit: (_) => _refresh(),
            ),
          ),
          FCheckbox(
            key: const ValueKey('k8s-all-namespaces'),
            value: _allNamespaces,
            onChange: (v) => setState(() {
              _allNamespaces = v;
              _refresh();
            }),
            label: const Text('All namespaces'),
          ),
          ContainerIconAction(
            icon: FLucideIcons.refreshCw,
            tooltip: 'Refresh',
            onPress: _loading ? null : _refresh,
          ),
        ],
      ),
    );
  }

  Widget _contextDropdown() {
    return SettingsSelect<String?>(
      key: const ValueKey('k8s-context'),
      hint: 'Context',
      value: _context,
      options: [
        (null, '(default context)'),
        for (final c in _contexts) (c, c),
      ],
      onChanged: (v) => setState(() {
        _context = v;
        _refresh();
      }),
    );
  }

  // ── Body ─────────────────────────────────────────────

  Widget _body() {
    if (_loading) return const Center(child: FCircularProgress());
    if (_error != null) {
      return YsEmptyState(icon: FLucideIcons.circleAlert, title: _error!);
    }
    if (_pods.isEmpty) {
      return YsEmptyState(
        icon: FLucideIcons.inbox,
        title: 'No pods. Tap refresh to scan.',
        action: FButton(
          autofocus: true,
          onPress: _refresh,
          child: const Text('Scan'),
        ),
      );
    }
    return _podList();
  }

  Widget _podList() {
    return ListView.builder(
      itemCount: _pods.length,
      itemBuilder: (_, i) {
        final p = _pods[i];
        return ContainerRow(
          key: ValueKey('pod-${p.namespace}-${p.name}'),
          title: p.name,
          subtitle: '${p.namespace}  •  ${p.ready}  •  ${p.status}',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ContainerIconAction(
                icon: FLucideIcons.terminal,
                tooltip: 'Exec',
                onPress: () => _execPod(p),
              ),
              ContainerIconAction(
                icon: FLucideIcons.fileText,
                tooltip: 'Logs',
                onPress: () => _openLogs(p),
              ),
              ContainerIconAction(
                icon: FLucideIcons.arrowLeftRight,
                tooltip: 'Forward port',
                onPress: () => _showForwardDialog(p),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Asks which container to target when the pod has several. Returns null
  /// when the dialog is dismissed; the sole container name for a single-
  /// container pod; null names for none.
  Future<(bool, String?)> _pickContainer(PodEntry p) async {
    final names =
        await _service().podContainers(widget.host, p.name, p.namespace);
    if (names.length > 1 && mounted) {
      final picked = await showYsDialog<String>(
        context,
        builder: (ctx) => YsDialog(
          title: 'Select container',
          body: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, n) in names.indexed)
                    FTile(
                      autofocus: i == 0,
                      title: Text(n,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onPress: () => Navigator.pop(ctx, n),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      return (picked != null, picked);
    }
    return (true, names.length == 1 ? names.first : null);
  }

  // ── Exec ─────────────────────────────────────────────

  Future<void> _execPod(PodEntry p) async {
    final (ok, container) = await _pickContainer(p);
    if (!ok) return;
    if (!mounted) return;
    await context.read<SessionProvider>().connect(
          widget.host,
          initialCommand: ContainerService.kubectlExecCommand(
              p.name, p.namespace, container),
        );
  }

  // ── Log panel ────────────────────────────────────────

  Future<void> _openLogs(PodEntry p) async {
    final (ok, container) = await _pickContainer(p);
    if (!ok) return;
    if (!mounted) return;
    _closeLogPanel();
    setState(() {
      _logPod = p;
      _logContainer = container;
      _logLines.clear();
    });
    _logSub = _service()
        .streamLogs(widget.host, p.name, p.namespace, _context,
            container: container)
        .listen(
      (line) {
        if (!mounted) return;
        setState(() {
          _logLines.add(line);
          if (_logLines.length > 500) _logLines.removeAt(0);
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_logScroll.hasClients) {
            _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
          }
        });
      },
      onError: (_) {
        if (mounted) {
          AppSnack.info(context, 'Log stream ended');
          _closeLogPanel();
        }
      },
      onDone: () {
        if (mounted) {
          AppSnack.info(context, 'Log stream ended');
          setState(() => _logPod = null);
        }
      },
    );
  }

  void _closeLogPanel() {
    _logSub?.cancel();
    _logSub = null;
    if (mounted) setState(() => _logPod = null);
  }

  Widget _logPanel() {
    final pod = _logPod!;
    return Container(
      height: 240,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: YsColors.border)),
      ),
      child: ContainerLogPanel(
        title: 'pod/${pod.name}'
            '${_logContainer != null ? '  •  $_logContainer' : ''}',
        lines: _logLines,
        controller: _logScroll,
        spinnerWhenEmpty: true,
        onClose: _closeLogPanel,
      ),
    );
  }

  // ── Port-forward dialog ──────────────────────────────

  Future<void> _showForwardDialog(PodEntry p) async {
    await showYsDialog<void>(
      context,
      builder: (_) => _PortForwardDialog(
        pod: p,
        onConfirm: (podPort, localPort) => _startForward(p, podPort, localPort),
      ),
    );
  }

  Future<void> _startForward(
      PodEntry p, int podPort, int localPort) async {
    try {
      final handle = await _service().startPodPortForward(
        widget.host,
        p.name,
        p.namespace,
        _context,
        podPort,
        localPort,
      );
      if (mounted) {
        setState(() => _forwards.add(handle));
        AppSnack.info(context,
            'Forwarding localhost:$localPort → pod/${p.name}:$podPort');
      } else {
        await handle.stop();
      }
    } catch (e) {
      if (!mounted) return;
      AppSnack.error(context, 'Port-forward failed: $e');
    }
  }

  Future<void> _stopForward(K8sForwardHandle h) async {
    await h.stop();
    if (mounted) setState(() => _forwards.remove(h));
  }

  // ── Active forwards bar ──────────────────────────────

  Widget _activeForwardsBar() {
    return Container(
      color: YsColors.card,
      padding: const EdgeInsets.symmetric(
          horizontal: YsSpace.s3, vertical: YsSpace.s1 + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ACTIVE FORWARDS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: YsColors.mutedForeground,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: YsSpace.s1),
          for (final f in _forwards)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'pod/${f.pod}  :${f.podPort} → localhost:${f.localPort}',
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.onOpenBrowser != null)
                  ContainerTextAction(
                    label: 'Open ↗',
                    onPress: () => widget
                        .onOpenBrowser!('http://localhost:${f.localPort}'),
                  ),
                ContainerTextAction(
                  label: '■ Stop',
                  onPress: () => _stopForward(f),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Port-forward dialog ──────────────────────────────────

class _PortForwardDialog extends StatefulWidget {
  const _PortForwardDialog(
      {required this.pod, required this.onConfirm});
  final PodEntry pod;
  final void Function(int podPort, int localPort) onConfirm;

  @override
  State<_PortForwardDialog> createState() => _PortForwardDialogState();
}

class _PortForwardDialogState extends State<_PortForwardDialog> {
  final _podPortCtrl = TextEditingController();
  final _localPortCtrl = TextEditingController();
  String? _podPortError;
  String? _localPortError;

  @override
  void dispose() {
    _podPortCtrl.dispose();
    _localPortCtrl.dispose();
    super.dispose();
  }

  String? _validatePort(String? v) {
    final n = int.tryParse(v ?? '');
    if (n == null || n < 1 || n > 65535) return '1–65535';
    return null;
  }

  void _submit() {
    final podErr = _validatePort(_podPortCtrl.text);
    final localErr = _validatePort(_localPortCtrl.text);
    if (podErr != null || localErr != null) {
      setState(() {
        _podPortError = podErr;
        _localPortError = localErr;
      });
      return;
    }
    final podPort = int.parse(_podPortCtrl.text);
    final localPort = int.parse(_localPortCtrl.text);
    Navigator.pop(context);
    widget.onConfirm(podPort, localPort);
  }

  @override
  Widget build(BuildContext context) {
    return YsDialog(
      title: 'Forward port',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'pod/${widget.pod.name}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: YsSpace.s3),
          FTextField(
            key: const ValueKey('k8s-pod-port'),
            control: .managed(
              controller: _podPortCtrl,
              onChange: (v) {
                if (_podPortError != null) setState(() => _podPortError = null);
                if (_localPortCtrl.text.isEmpty) {
                  _localPortCtrl.text = v.text;
                }
              },
            ),
            label: const Text('Pod port'),
            keyboardType: TextInputType.number,
            autofocus: true,
            textInputAction: TextInputAction.next,
            error: _podPortError == null ? null : Text(_podPortError!),
          ),
          const SizedBox(height: YsSpace.s2),
          FTextField(
            key: const ValueKey('k8s-local-port'),
            control: .managed(
              controller: _localPortCtrl,
              onChange: (_) {
                if (_localPortError != null) {
                  setState(() => _localPortError = null);
                }
              },
            ),
            label: const Text('Local port'),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmit: (_) => _submit(),
            error: _localPortError == null ? null : Text(_localPortError!),
          ),
        ],
      ),
      actions: [
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FButton(
          variant: FButtonVariant.primary,
          onPress: _submit,
          child: const Text('Start Forward'),
        ),
      ],
    );
  }
}
