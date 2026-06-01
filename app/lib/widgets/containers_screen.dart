import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/container_entry.dart';
import '../models/host.dart';
import '../providers/session_provider.dart';
import '../services/container_service.dart';
import '../services/ssh_service.dart';
import '../theme/app_theme.dart';

class ContainersScreen extends StatefulWidget {
  const ContainersScreen({super.key});

  @override
  State<ContainersScreen> createState() => _ContainersScreenState();
}

enum _Tab { docker, kubernetes }

class _ContainersScreenState extends State<ContainersScreen> {
  ContainerService? _service;
  String? _sessionId; // active session id used as source
  _Tab _tab = _Tab.docker;

  RuntimeStatus? _runtimes;
  List<ContainerEntry> _containers = [];
  List<PodEntry> _pods = [];
  String _namespace = 'default';
  bool _allNamespaces = false;

  bool _loading = false;
  String? _error;

  late final TextEditingController _nsController;

  @override
  void initState() {
    super.initState();
    _nsController = TextEditingController(text: _namespace);
  }

  @override
  void dispose() {
    _nsController.dispose();
    super.dispose();
  }

  ContainerService _ensureService() {
    _service ??= ContainerService(context.read<SshService>());
    return _service!;
  }

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<SessionProvider>().sessions;
    if (sessions.isEmpty) {
      return const _CenterHint(
        icon: Icons.terminal,
        message: 'Open an SSH session first, then come back to browse containers.',
      );
    }
    // Default to the active/first session.
    _sessionId ??= sessions.first.id;
    final selected = sessions.firstWhere(
      (s) => s.id == _sessionId,
      orElse: () => sessions.first,
    );
    _sessionId = selected.id;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  value: _sessionId,
                  isExpanded: true,
                  items: [
                    for (final s in sessions)
                      DropdownMenuItem(value: s.id, child: Text(s.title)),
                  ],
                  onChanged: (v) => setState(() {
                    _sessionId = v;
                    _runtimes = null;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: _loading ? null : _refresh,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(children: [
            _tabButton(_Tab.docker, 'Docker'),
            const SizedBox(width: 8),
            _tabButton(_Tab.kubernetes, 'Kubernetes'),
          ]),
          if (_tab == _Tab.kubernetes) _namespaceControls(),
          const SizedBox(height: 8),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _tabButton(_Tab tab, String label) {
    final active = _tab == tab;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (_) => setState(() {
        _tab = tab;
        _containers = [];
        _pods = [];
        _error = null;
      }),
    );
  }

  Widget _namespaceControls() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        SizedBox(
          width: 200,
          child: TextField(
            enabled: !_allNamespaces,
            decoration: const InputDecoration(labelText: 'Namespace', isDense: true),
            controller: _nsController,
            onSubmitted: (v) {
              _namespace = v.trim().isEmpty ? 'default' : v.trim();
              _refresh();
            },
          ),
        ),
        const SizedBox(width: 12),
        Row(children: [
          Checkbox(
            value: _allNamespaces,
            onChanged: (v) => setState(() {
              _allNamespaces = v ?? false;
              _refresh();
            }),
          ),
          const Text('All namespaces'),
        ]),
      ]),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final host = _hostForSelected();
    if (host == null) {
      return const _CenterHint(icon: Icons.link_off, message: 'Session not found.');
    }
    final runtimes = _runtimes;
    if (runtimes == null) {
      return _CenterHint(
        icon: Icons.search,
        message: 'Tap refresh to scan for Docker / Kubernetes.',
        actionLabel: 'Scan',
        onAction: _refresh,
      );
    }

    final avail = _availabilityFor(runtimes);
    final runtimeName = _tab == _Tab.docker ? 'docker' : 'kubectl';

    if (avail == RuntimeAvailability.notInstalled) {
      return _HintCard(
        title: '$runtimeName is not installed on this host',
        command: ContainerService.installHint(runtimeName, host.detectedOs),
      );
    }
    if (avail == RuntimeAvailability.noPermission) {
      return _HintCard(
        title: 'No permission to use $runtimeName',
        command: ContainerService.permissionHint(runtimeName),
      );
    }
    if (_error != null) {
      return _CenterHint(icon: Icons.error_outline, message: _error!);
    }
    return _tab == _Tab.docker ? _dockerList() : _podList();
  }

  Widget _dockerList() {
    if (_containers.isEmpty) {
      return const _CenterHint(icon: Icons.inbox, message: 'No running containers.');
    }
    return ListView.separated(
      itemCount: _containers.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final c = _containers[i];
        return ListTile(
          title: Text(c.name),
          subtitle: Text('${c.image}  •  ${c.status}'),
          trailing: FilledButton.icon(
            icon: const Icon(Icons.terminal, size: 16),
            label: const Text('Exec'),
            onPressed: () => _execContainer(c),
          ),
        );
      },
    );
  }

  Widget _podList() {
    if (_pods.isEmpty) {
      return const _CenterHint(icon: Icons.inbox, message: 'No pods.');
    }
    return ListView.separated(
      itemCount: _pods.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final p = _pods[i];
        return ListTile(
          title: Text(p.name),
          subtitle: Text('${p.namespace}  •  ${p.ready}  •  ${p.status}'),
          trailing: FilledButton.icon(
            icon: const Icon(Icons.terminal, size: 16),
            label: const Text('Exec'),
            onPressed: () => _execPod(p),
          ),
        );
      },
    );
  }

  // ── Actions ───────────────────────────────────────────
  Future<void> _refresh() async {
    _namespace = _nsController.text.trim().isEmpty ? 'default' : _nsController.text.trim();
    final host = _hostForSelected();
    if (host == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = _ensureService();
      _runtimes = await svc.detectRuntimes(host);
      if (_availabilityFor(_runtimes!) == RuntimeAvailability.available) {
        if (_tab == _Tab.docker) {
          _containers = await svc.listDockerContainers(host);
        } else {
          _pods = await svc.listPods(host,
              namespace: _namespace, allNamespaces: _allNamespaces);
        }
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _execContainer(ContainerEntry c) async {
    if (!mounted) return;
    final host = _hostForSelected();
    if (host == null) return;
    final sessionProvider = context.read<SessionProvider>();
    await sessionProvider.connect(
      host,
      initialCommand: ContainerService.dockerExecCommand(c.id),
    );
  }

  Future<void> _execPod(PodEntry p) async {
    final host = _hostForSelected();
    if (host == null) return;
    String? container;
    final names = await _ensureService().podContainers(host, p.name, p.namespace);
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
      if (container == null) return; // cancelled
    } else if (names.length == 1) {
      container = names.first;
    }
    if (!mounted) return;
    final sessionProvider = context.read<SessionProvider>();
    await sessionProvider.connect(
      host,
      initialCommand:
          ContainerService.kubectlExecCommand(p.name, p.namespace, container),
    );
  }

  RuntimeAvailability _availabilityFor(RuntimeStatus r) =>
      _tab == _Tab.docker ? r.docker : r.kubectl;

  Host? _hostForSelected() {
    final id = _sessionId;
    if (id == null) return null;
    return context.read<SessionProvider>().hostForSession(id);
  }
}

class _CenterHint extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _CenterHint({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  final String title;
  final String command;
  const _HintCard({required this.title, required this.command});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              SelectableText(
                command,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy command'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: command));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
