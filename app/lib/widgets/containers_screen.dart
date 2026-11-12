import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/container_entry.dart';
import '../models/host.dart';
import 'kubernetes_panel.dart';
import 'docker_panel.dart';
import 'compose_panel.dart';
import '../providers/session_provider.dart';
import '../services/container_service.dart';
import '../services/ssh_service.dart';
import '../theme/app_theme.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import 'settings/settings_tiles.dart';

class ContainersScreen extends StatefulWidget {
  const ContainersScreen({super.key, this.onOpenBrowser});
  final void Function(String url)? onOpenBrowser;

  @override
  State<ContainersScreen> createState() => _ContainersScreenState();
}

enum _Tab { docker, compose, kubernetes }

class _ContainersScreenState extends State<ContainersScreen> {
  ContainerService? _service;
  String? _sessionId;
  _Tab _tab = _Tab.docker;

  RuntimeStatus? _runtimes;
  bool _loading = false;
  String? _error;

  ContainerService _ensureService() {
    _service ??= ContainerService(context.read<SshService>());
    return _service!;
  }

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<SessionProvider>().sshSessions;
    if (sessions.isEmpty) {
      return const YsEmptyState(
        icon: FLucideIcons.terminal,
        title: 'Open an SSH session first, then come back to browse containers.',
      );
    }
    _sessionId ??= sessions.first.id;
    final selected = sessions.firstWhere(
      (s) => s.id == _sessionId,
      orElse: () => sessions.first,
    );
    _sessionId = selected.id;

    return Padding(
      padding: const EdgeInsets.all(YsSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SettingsSelect<String>(
                  key: const ValueKey('containers-session'),
                  width: double.infinity,
                  value: _sessionId!,
                  options: [for (final s in sessions) (s.id, s.title)],
                  onChanged: (v) => setState(() {
                    _sessionId = v;
                    _runtimes = null;
                    // Drop the previous session's scan error so it isn't shown
                    // against the newly-selected session.
                    _error = null;
                  }),
                ),
              ),
              const SizedBox(width: YsSpace.s3),
              Tooltip(
                message: 'Rescan runtimes',
                excludeFromSemantics: true,
                child: FButton.icon(
                  variant: .outline,
                  semanticsLabel: 'Rescan runtimes',
                  onPress: _loading ? null : _refresh,
                  child: const Icon(FLucideIcons.refreshCw),
                ),
              ),
            ],
          ),
          const SizedBox(height: YsSpace.s2),
          FTabs(
            key: const ValueKey('containers-tabs'),
            control: .lifted(
              index: _tab.index,
              onChange: (i) => setState(() => _tab = _Tab.values[i]),
            ),
            children: [
              FTabEntry(
                  label: const Text('Docker'), child: const SizedBox.shrink()),
              FTabEntry(
                  label: const Text('Compose'), child: const SizedBox.shrink()),
              FTabEntry(
                  label: const Text('Kubernetes'),
                  child: const SizedBox.shrink()),
            ],
          ),
          const SizedBox(height: YsSpace.s2),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: FCircularProgress());
    final host = _hostForSelected();
    if (host == null) {
      return const YsEmptyState(
        icon: FLucideIcons.unlink,
        title: 'Session not found.',
      );
    }
    final runtimes = _runtimes;
    if (runtimes == null) {
      if (_error != null) {
        return YsEmptyState(
          icon: FLucideIcons.circleAlert,
          title: _error!,
          action: FButton(
            autofocus: true,
            onPress: _refresh,
            child: const Text('Retry'),
          ),
        );
      }
      return YsEmptyState(
        icon: FLucideIcons.search,
        title: 'Tap refresh to scan for Docker / Kubernetes.',
        action: FButton(
          autofocus: true,
          onPress: _refresh,
          child: const Text('Scan'),
        ),
      );
    }

    final avail = _availabilityFor(runtimes);
    final runtimeName = _tab == _Tab.kubernetes ? 'kubectl' : 'docker';

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

    // Runtime is available — the panels load their own data on init. Each is
    // remounted (fresh initState) whenever the session changes, because
    // switching sessions sets `_runtimes = null`, which unmounts the panel
    // until the next scan.
    final svc = _ensureService();
    switch (_tab) {
      case _Tab.docker:
        return DockerPanel(host: host, service: svc);
      case _Tab.compose:
        return ComposePanel(host: host, service: svc);
      case _Tab.kubernetes:
        return KubernetesPanel(host: host, onOpenBrowser: widget.onOpenBrowser);
    }
  }

  Future<void> _refresh() async {
    final host = _hostForSelected();
    if (host == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      _runtimes = await _ensureService().detectRuntimes(host);
    } catch (e) {
      // Clear stale runtimes so _body() reaches the error branch instead of
      // silently rendering the previous scan's panel.
      _runtimes = null;
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  RuntimeAvailability _availabilityFor(RuntimeStatus r) =>
      _tab == _Tab.kubernetes ? r.kubectl : r.docker;

  Host? _hostForSelected() {
    final id = _sessionId;
    if (id == null) return null;
    return context.read<SessionProvider>().hostForSession(id);
  }
}

class _HintCard extends StatelessWidget {
  final String title;
  final String command;
  const _HintCard({required this.title, required this.command});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: FCard(
            child: Padding(
              padding: const EdgeInsets.all(YsSpace.s1),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: YsColors.foreground,
                    ),
                  ),
                  const SizedBox(height: YsSpace.s3),
                  SelectableText(
                    command,
                    style: const TextStyle(fontFamily: kYsMonoFontFamily),
                  ),
                  const SizedBox(height: YsSpace.s3),
                  FButton(
                    mainAxisSize: MainAxisSize.min,
                    prefix: const Icon(FLucideIcons.copy),
                    onPress: () {
                      Clipboard.setData(ClipboardData(text: command));
                      AppSnack.info(context, 'Copied');
                    },
                    child: const Text('Copy command'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
