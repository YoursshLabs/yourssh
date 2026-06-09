import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/container_entry.dart';
import '../models/host.dart';
import '../providers/session_provider.dart';
import '../services/container_service.dart';
import '../services/ssh_service.dart';
import '../theme/app_theme.dart';

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
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (_contexts.isNotEmpty) _contextDropdown(),
          SizedBox(
            width: 180,
            child: TextField(
              enabled: !_allNamespaces,
              decoration: const InputDecoration(
                  labelText: 'Namespace', isDense: true),
              controller: _nsCtrl,
              onSubmitted: (_) => _refresh(),
            ),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Checkbox(
              value: _allNamespaces,
              onChanged: (v) => setState(() {
                _allNamespaces = v ?? false;
                _refresh();
              }),
            ),
            const Text('All namespaces'),
          ]),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
    );
  }

  Widget _contextDropdown() {
    return DropdownButton<String?>(
      value: _context,
      hint: const Text('Context'),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('(default context)'),
        ),
        for (final c in _contexts)
          DropdownMenuItem<String?>(value: c, child: Text(c)),
      ],
      onChanged: (v) => setState(() {
        _context = v;
        _refresh();
      }),
    );
  }

  // ── Body ─────────────────────────────────────────────

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
          ],
        ),
      );
    }
    if (_pods.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox, size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            const Text('No pods. Tap refresh to scan.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: _refresh, child: const Text('Scan')),
          ],
        ),
      );
    }
    return _podList();
  }

  Widget _podList() {
    return ListView.separated(
      itemCount: _pods.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final p = _pods[i];
        return ListTile(
          title: Text(p.name),
          subtitle:
              Text('${p.namespace}  •  ${p.ready}  •  ${p.status}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.terminal, size: 18),
                tooltip: 'Exec',
                onPressed: () => _execPod(p),
              ),
              IconButton(
                icon: const Icon(Icons.article_outlined, size: 18),
                tooltip: 'Logs',
                onPressed: () => _openLogs(p),
              ),
              IconButton(
                icon: const Icon(Icons.swap_horiz, size: 18),
                tooltip: 'Forward port',
                onPressed: () => _showForwardDialog(p),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Exec ─────────────────────────────────────────────

  Future<void> _execPod(PodEntry p) async {
    String? container;
    final names =
        await _service().podContainers(widget.host, p.name, p.namespace);
    if (names.length > 1 && mounted) {
      container = await showDialog<String>(
        context: context,
        builder: (_) => SimpleDialog(
          title: const Text('Select container'),
          children: [
            for (final n in names)
              SimpleDialogOption(
                child: Text(n),
                onPressed: () => Navigator.pop(context, n),
              ),
          ],
        ),
      );
      if (container == null) return;
    } else if (names.length == 1) {
      container = names.first;
    }
    if (!mounted) return;
    await context.read<SessionProvider>().connect(
          widget.host,
          initialCommand: ContainerService.kubectlExecCommand(
              p.name, p.namespace, container),
        );
  }

  // ── Log panel ────────────────────────────────────────

  Future<void> _openLogs(PodEntry p) async {
    String? container;
    final names =
        await _service().podContainers(widget.host, p.name, p.namespace);
    if (names.length > 1 && mounted) {
      container = await showDialog<String>(
        context: context,
        builder: (_) => SimpleDialog(
          title: const Text('Select container'),
          children: [
            for (final n in names)
              SimpleDialogOption(
                child: Text(n),
                onPressed: () => Navigator.pop(context, n),
              ),
          ],
        ),
      );
      if (container == null) return;
    } else if (names.length == 1) {
      container = names.first;
    }
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Log stream ended')),
          );
          _closeLogPanel();
        }
      },
      onDone: () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Log stream ended')),
          );
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
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.article_outlined,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'pod/${pod.name}'
                    '${_logContainer != null ? '  •  $_logContainer' : ''}',
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Close logs',
                  onPressed: _closeLogPanel,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _logLines.isEmpty
                ? const Center(
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child:
                            CircularProgressIndicator(strokeWidth: 2)))
                : ListView.builder(
                    controller: _logScroll,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    itemCount: _logLines.length,
                    itemBuilder: (_, i) => Text(
                      _logLines[i],
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Port-forward dialog ──────────────────────────────

  Future<void> _showForwardDialog(PodEntry p) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _PortForwardDialog(
        pod: p,
        onConfirm: (podPort, localPort) =>
            _startForward(p, podPort, localPort),
      ),
    );
  }

  Future<void> _startForward(
      PodEntry p, int podPort, int localPort) async {
    final messenger = ScaffoldMessenger.of(context);
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
        messenger.showSnackBar(SnackBar(
          content: Text(
              'Forwarding localhost:$localPort → pod/${p.name}:$podPort'),
        ));
      } else {
        await handle.stop();
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Port-forward failed: $e')),
      );
    }
  }

  Future<void> _stopForward(K8sForwardHandle h) async {
    await h.stop();
    if (mounted) setState(() => _forwards.remove(h));
  }

  // ── Active forwards bar ──────────────────────────────

  Widget _activeForwardsBar() {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ACTIVE FORWARDS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textTertiary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          for (final f in _forwards)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'pod/${f.pod}  :${f.podPort} → localhost:${f.localPort}',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.onOpenBrowser != null)
                    TextButton(
                      onPressed: () => widget.onOpenBrowser!(
                          'http://localhost:${f.localPort}'),
                      style: TextButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Open ↗',
                          style: TextStyle(fontSize: 12)),
                    ),
                  TextButton(
                    onPressed: () => _stopForward(f),
                    style: TextButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('■ Stop',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
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
  final _formKey = GlobalKey<FormState>();
  final _podPortCtrl = TextEditingController();
  final _localPortCtrl = TextEditingController();

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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Forward port'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('pod/${widget.pod.name}',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _podPortCtrl,
              decoration: const InputDecoration(
                  labelText: 'Pod port', isDense: true),
              keyboardType: TextInputType.number,
              autofocus: true,
              validator: _validatePort,
              onChanged: (v) {
                if (_localPortCtrl.text.isEmpty) {
                  _localPortCtrl.text = v;
                }
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _localPortCtrl,
              decoration: const InputDecoration(
                  labelText: 'Local port', isDense: true),
              keyboardType: TextInputType.number,
              validator: _validatePort,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final podPort = int.parse(_podPortCtrl.text);
            final localPort = int.parse(_localPortCtrl.text);
            Navigator.pop(context);
            widget.onConfirm(podPort, localPort);
          },
          child: const Text('Start Forward'),
        ),
      ],
    );
  }
}
