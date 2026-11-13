import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../models/port_forward.dart';
import '../providers/host_provider.dart';
import '../providers/port_forward_provider.dart';
import '../services/port_forward_service.dart';
import 'ys_form_controls.dart';
import 'ys_menu.dart';

class PortForwardingScreen extends StatefulWidget {
  const PortForwardingScreen({super.key});

  @override
  State<PortForwardingScreen> createState() => _PortForwardingScreenState();
}

class _PortForwardingScreenState extends State<PortForwardingScreen> {
  bool _showPanel = false;
  PortForward? _editing;

  void _openEditor([PortForward? fwd]) => setState(() {
    _editing = fwd;
    _showPanel = true;
  });

  void _closePanel() => setState(() {
    _showPanel = false;
    _editing = null;
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PortForwardProvider>();

    return Row(
      children: [
        Expanded(
          child: ColoredBox(
            color: YsColors.background,
            child: Column(
              children: [
                _TopBar(onAdd: _openEditor),
                Expanded(
                  child: provider.forwards.isEmpty
                      ? YsEmptyState(
                          icon: FLucideIcons.arrowLeftRight,
                          title: 'No rules yet',
                          message:
                              'Create local, remote, or SOCKS5 port forwarding rules',
                          action: FButton(
                            onPress: _openEditor,
                            child: const Text('+ New Rule'),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(YsSpace.s5),
                          itemCount: provider.forwards.length,
                          itemBuilder: (_, i) => _ForwardTile(
                            forward: provider.forwards[i],
                            onEdit: _openEditor,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        if (_showPanel)
          _ForwardPanel(
            key: ValueKey(_editing?.id ?? 'new'),
            initial: _editing,
            onClose: _closePanel,
            onSave: (forward) async {
              final provider = context.read<PortForwardProvider>();
              final service = context.read<PortForwardService>();
              if (_editing != null) {
                // A running tunnel keeps its old config — stop before saving.
                if (service.isRunning(forward.id)) {
                  await service.stop(forward.id);
                }
                await provider.update(forward);
              } else {
                await provider.add(forward);
              }
              if (mounted) _closePanel();
            },
          ),
      ],
    );
  }
}

/// Section bar: title left, primary action right, hairline below.
class _Bar extends StatelessWidget {
  final double height;
  final Widget child;
  const _Bar({required this.height, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    padding: const EdgeInsets.symmetric(horizontal: YsSpace.s4),
    decoration: const BoxDecoration(
      color: YsColors.sidebar,
      border: Border(bottom: BorderSide(color: YsColors.border)),
    ),
    child: child,
  );
}

class _TopBar extends StatelessWidget {
  final VoidCallback onAdd;
  const _TopBar({required this.onAdd});

  @override
  Widget build(BuildContext context) => _Bar(
    height: 52,
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'Port Forwarding',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: YsColors.foreground,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        FButton(
          size: .sm,
          mainAxisSize: MainAxisSize.min,
          prefix: const Icon(FLucideIcons.plus),
          onPress: onAdd,
          child: const Text('New rule'),
        ),
      ],
    ),
  );
}

class _ForwardTile extends StatefulWidget {
  final PortForward forward;
  final void Function(PortForward) onEdit;
  const _ForwardTile({required this.forward, required this.onEdit});

  @override
  State<_ForwardTile> createState() => _ForwardTileState();
}

class _ForwardTileState extends State<_ForwardTile> {
  bool _hovered = false;
  bool _hasFocus = false;

  Future<void> _duplicate() async {
    final fwd = widget.forward;
    await context.read<PortForwardProvider>().add(
      PortForward(
        label: '${fwd.label} (copy)',
        type: fwd.type,
        localHost: fwd.localHost,
        localPort: fwd.localPort,
        remoteHost: fwd.remoteHost,
        remotePort: fwd.remotePort,
        hostId: fwd.hostId,
        autoStart: false, // a copy must never race the original on launch
      ),
    );
  }

  Future<void> _delete() async {
    final service = context.read<PortForwardService>();
    final provider = context.read<PortForwardProvider>();
    await service.stop(widget.forward.id);
    await provider.delete(widget.forward.id);
  }

  Future<void> _showContextMenu(Offset globalPos) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx,
        globalPos.dy,
        globalPos.dx + 1,
        globalPos.dy + 1,
      ),
      color: kYsMenuColor,
      shape: kYsMenuShape,
      items: [
        ysMenuItem('duplicate', FLucideIcons.copy, 'Duplicate'),
        ysMenuItem('edit', FLucideIcons.pencil, 'Edit'),
        const PopupMenuDivider(),
        ysMenuItem('delete', FLucideIcons.trash2, 'Delete'),
      ],
    );
    if (!mounted) return;

    switch (result) {
      case 'duplicate':
        await _duplicate();
      case 'edit':
        widget.onEdit(widget.forward);
      case 'delete':
        await _delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final fwd = widget.forward;
    final statusColor = switch (fwd.status) {
      ForwardStatus.active => YsColors.ok,
      ForwardStatus.error => YsColors.error,
      ForwardStatus.connecting || ForwardStatus.reconnecting => YsColors.warn,
      ForwardStatus.idle => YsColors.off,
    };
    final running =
        fwd.status == ForwardStatus.active ||
        fwd.status == ForwardStatus.connecting ||
        fwd.status == ForwardStatus.reconnecting;

    return Padding(
      padding: const EdgeInsets.only(bottom: YsSpace.s2),
      child: GestureDetector(
        onSecondaryTapUp: (details) => _showContextMenu(details.globalPosition),
        child: Focus(
         canRequestFocus: false,
         skipTraversal: true,
         onFocusChange: (f) => setState(() => _hasFocus = f),
         child: settingsTileGroup(
          children: [
            FTile.raw(
              onPress: () => widget.onEdit(fwd),
              onHoverChange: (h) => setState(() => _hovered = h),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: YsSpace.s3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                fwd.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: YsColors.foreground,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: YsSpace.s2),
                            YsTag(fwd.typeLabel),
                            if (fwd.status == ForwardStatus.active) ...[
                              const SizedBox(width: 6),
                              YsStatusBadge(
                                '${fwd.activeConnections} conn',
                                status: YsStatus.ok,
                              ),
                            ],
                            if (fwd.status == ForwardStatus.reconnecting) ...[
                              const SizedBox(width: 6),
                              const YsStatusBadge(
                                'reconnecting…',
                                status: YsStatus.warn,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          fwd.summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: YsColors.mutedForeground,
                            fontSize: 11,
                            fontFamily: kYsMonoFontFamily,
                            fontFamilyFallback: kYsMonoFontFallback,
                          ),
                        ),
                        if (fwd.status == ForwardStatus.error &&
                            fwd.errorMessage != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            fwd.errorMessage!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: YsColors.error,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: YsSpace.s2),
                  _IconAction(
                    icon: running ? FLucideIcons.square : FLucideIcons.play,
                    color: running ? YsColors.error : YsColors.primary,
                    tooltip: running ? 'Stop' : 'Start',
                    onPress: () {
                      final service = context.read<PortForwardService>();
                      if (running) {
                        service.stop(fwd.id);
                      } else {
                        service.start(fwd);
                      }
                    },
                  ),
                  // Space is always reserved so hover/focus never reflows
                  // the title; shown on hover or focus inside the row.
                  const SizedBox(width: 6),
                  Visibility(
                    visible: _hovered || _hasFocus,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: _IconAction(
                      icon: FLucideIcons.trash2,
                      color: YsColors.error,
                      tooltip: 'Delete',
                      onPress: _delete,
                    ),
                  ),
                ],
              ),
            ),
          ],
         ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPress;
  const _IconAction({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPress,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    excludeFromSemantics: true,
    child: FButton.icon(
      variant: .outline,
      size: .xs,
      semanticsLabel: tooltip,
      onPress: onPress,
      child: Icon(icon, color: color),
    ),
  );
}

// ── Forward Panel ─────────────────────────────────────────

class _ForwardPanel extends StatefulWidget {
  final PortForward? initial;
  final VoidCallback onClose;
  final Future<void> Function(PortForward) onSave;
  const _ForwardPanel({
    super.key,
    this.initial,
    required this.onClose,
    required this.onSave,
  });

  @override
  State<_ForwardPanel> createState() => _ForwardPanelState();
}

class _ForwardPanelState extends State<_ForwardPanel> {
  final _label = TextEditingController();
  final _localHost = TextEditingController(text: '127.0.0.1');
  final _localPort = TextEditingController();
  final _remoteHost = TextEditingController();
  final _remotePort = TextEditingController();
  ForwardType _type = ForwardType.local;
  String? _selectedHostId;
  bool _autoStart = false;
  bool _saving = false;

  /// Field key → message, filled by [_validate] on submit and cleared per
  /// field as the user edits it.
  final Map<String, String> _errors = {};

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _label.text = init.label;
      _localHost.text = init.localHost;
      _localPort.text = init.localPort.toString();
      _remoteHost.text = init.remoteHost;
      _remotePort.text = init.remotePort == 0 ? '' : init.remotePort.toString();
      _type = init.type;
      _selectedHostId = init.hostId;
      _autoStart = init.autoStart;
    }
  }

  @override
  void dispose() {
    for (final c in [_label, _localHost, _localPort, _remoteHost, _remotePort]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _validate() {
    String? required(TextEditingController c) =>
        c.text.trim().isEmpty ? 'Required' : null;
    String? number(TextEditingController c) {
      final n = int.tryParse(c.text);
      return n == null || n < 1 || n > 65535 ? 'Invalid (1–65535)' : null;
    }
    final found = <String, String?>{
      'label': required(_label),
      'localHost': required(_localHost),
      'localPort': number(_localPort),
      if (_type != ForwardType.dynamic) ...{
        'remoteHost': required(_remoteHost),
        'remotePort': number(_remotePort),
      },
    };
    _errors
      ..clear()
      ..addAll({
        for (final e in found.entries)
          if (e.value != null) e.key: e.value!,
      });
    setState(() {});
    return _errors.isEmpty;
  }

  Future<void> _submit() async {
    if (_saving || !_validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(
        PortForward(
          id: widget.initial?.id,
          label: _label.text.trim(),
          type: _type,
          localHost: _localHost.text.trim(),
          localPort: int.parse(_localPort.text),
          remoteHost: _remoteHost.text.trim(),
          remotePort: int.tryParse(_remotePort.text) ?? 0,
          hostId: _selectedHostId,
          autoStart: _autoStart,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    String errorKey,
    String key,
    TextEditingController ctrl,
    String label, {
    bool autofocus = false,
    bool number = false,
    bool mono = false,
  }) => FTextField(
    key: ValueKey(key),
    control: .managed(
      controller: ctrl,
      onChange: (_) {
        if (_errors.containsKey(errorKey)) {
          setState(() => _errors.remove(errorKey));
        }
      },
    ),
    label: Text(label),
    autofocus: autofocus,
    textInputAction: TextInputAction.done,
    // Keep the caret in the field when Enter hits an invalid form.
    onEditingComplete: ctrl.clearComposing,
    onSubmit: (_) => _submit(),
    keyboardType: number ? TextInputType.number : null,
    inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
    autocorrect: false,
    enableSuggestions: false,
    error: _errors[errorKey] == null ? null : Text(_errors[errorKey]!),
    style: mono
        ? .delta(
            contentTextStyle: .delta([
              .base(
                const .delta(
                  fontFamily: kYsMonoFontFamily,
                  fontFamilyFallback: kYsMonoFontFallback,
                ),
              ),
            ]),
          )
        : const .context(),
  );

  Widget _hostPortRow({
    required String hostKey,
    required String hostField,
    required TextEditingController host,
    required String hostLabel,
    required String portKey,
    required String portField,
    required TextEditingController port,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        flex: 2,
        child: _field(hostKey, hostField, host, hostLabel, mono: true),
      ),
      const SizedBox(width: YsSpace.s2),
      SizedBox(
        width: 90,
        child: _field(portKey, portField, port, 'Port', number: true),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final hosts = context.watch<HostProvider>().hosts;
    final isDynamic = _type == ForwardType.dynamic;

    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: YsColors.sidebar,
        border: Border(left: BorderSide(color: YsColors.border)),
      ),
      child: Column(
        children: [
          _Bar(
            height: 52,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.initial == null
                        ? 'New Port Forward Rule'
                        : 'Edit Port Forward Rule',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: YsColors.foreground,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SettingsIconButton(
                  icon: FLucideIcons.x,
                  tooltip: 'Close',
                  onPress: widget.onClose,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                YsSpace.s4,
                YsSpace.s4,
                YsSpace.s4,
                YsSpace.s5,
              ),
              children: [
                _field('label', 'pf-label', _label, 'Label', autofocus: true),
                const SizedBox(height: YsSpace.s3),
                const SettingsCaption('Type'),
                const SizedBox(height: YsSpace.s1),
                SettingsSelect<ForwardType>(
                  key: const ValueKey('pf-type'),
                  width: double.infinity,
                  value: _type,
                  options: const [
                    (ForwardType.local, 'Local'),
                    (ForwardType.remote, 'Remote'),
                    (ForwardType.dynamic, 'Dynamic SOCKS5'),
                  ],
                  onChanged: (v) => setState(() => _type = v),
                ),
                const SizedBox(height: YsSpace.s3),
                _hostPortRow(
                  hostKey: 'localHost',
                  hostField: 'pf-local-host',
                  host: _localHost,
                  hostLabel: 'Local Host',
                  portKey: 'localPort',
                  portField: 'pf-local-port',
                  port: _localPort,
                ),
                if (!isDynamic) ...[
                  const SizedBox(height: YsSpace.s3),
                  _hostPortRow(
                    hostKey: 'remoteHost',
                    hostField: 'pf-remote-host',
                    host: _remoteHost,
                    hostLabel: 'Remote Host',
                    portKey: 'remotePort',
                    portField: 'pf-remote-port',
                    port: _remotePort,
                  ),
                ],
                const SizedBox(height: YsSpace.s3),
                const SettingsCaption('SSH Host (optional)'),
                const SizedBox(height: YsSpace.s1),
                SettingsSelect<String?>(
                  key: const ValueKey('pf-host'),
                  width: double.infinity,
                  hint: 'Select host',
                  value: hosts.any((h) => h.id == _selectedHostId)
                      ? _selectedHostId
                      : null,
                  options: [for (final h in hosts) (h.id, h.label)],
                  onChanged: (v) => setState(() => _selectedHostId = v),
                ),
                const SizedBox(height: YsSpace.s3),
                FCheckbox(
                  key: const ValueKey('pf-autostart'),
                  value: _autoStart,
                  onChange: (v) => setState(() => _autoStart = v),
                  label: const Text('Auto-start on launch'),
                ),
                const SizedBox(height: YsSpace.s5),
                FButton(
                  onPress: _saving ? null : _submit,
                  prefix: _saving ? const FCircularProgress() : null,
                  child: Text(widget.initial == null ? 'Add Rule' : 'Save'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
