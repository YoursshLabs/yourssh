import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/port_forward.dart';
import '../providers/host_provider.dart';
import '../providers/port_forward_provider.dart';
import '../services/port_forward_service.dart';
import '../theme/app_theme.dart';

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
          child: Container(
            color: AppColors.bg,
            child: Column(
              children: [
                _TopBar(onAdd: _openEditor),
                Expanded(
                  child: provider.forwards.isEmpty
                      ? _EmptyState(onAdd: _openEditor)
                      : ListView.builder(
                          padding: const EdgeInsets.all(24),
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
                if (service.isRunning(forward.id)) await service.stop(forward.id);
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

class _TopBar extends StatelessWidget {
  final VoidCallback onAdd;
  const _TopBar({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          const Text('Port Forwarding',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(6)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 14, color: Colors.black),
                  SizedBox(width: 6),
                  Text('NEW RULE',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
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

  Future<void> _duplicate() async {
    final fwd = widget.forward;
    await context.read<PortForwardProvider>().add(PortForward(
          label: '${fwd.label} (copy)',
          type: fwd.type,
          localHost: fwd.localHost,
          localPort: fwd.localPort,
          remoteHost: fwd.remoteHost,
          remotePort: fwd.remotePort,
          hostId: fwd.hostId,
          autoStart: false, // a copy must never race the original on launch
        ));
  }

  Future<void> _delete() async {
    final service = context.read<PortForwardService>();
    final provider = context.read<PortForwardProvider>();
    await service.stop(widget.forward.id);
    await provider.delete(widget.forward.id);
  }

  Future<void> _showContextMenu(Offset globalPos) async {
    PopupMenuItem<String> item(String value, IconData icon, String label,
        {Color color = const Color(0xFFCCCCCC)}) {
      return PopupMenuItem(
        value: value,
        child: Row(children: [
          Icon(icon, size: 14, color: const Color(0xFFAAAAAA)),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontSize: 13)),
        ]),
      );
    }

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPos.dx, globalPos.dy, globalPos.dx + 1, globalPos.dy + 1,
      ),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      items: [
        item('duplicate', Icons.copy_outlined, 'Duplicate'),
        item('edit', Icons.edit_outlined, 'Edit'),
        const PopupMenuDivider(),
        item('delete', Icons.delete_outlined, 'Delete', color: AppColors.red),
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
      ForwardStatus.active => AppColors.accent,
      ForwardStatus.error => AppColors.red,
      ForwardStatus.connecting || ForwardStatus.reconnecting => AppColors.orange,
      ForwardStatus.idle => AppColors.textTertiary,
    };
    final running = fwd.status == ForwardStatus.active ||
        fwd.status == ForwardStatus.connecting ||
        fwd.status == ForwardStatus.reconnecting;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => widget.onEdit(fwd),
        onSecondaryTapUp: (details) => _showContextMenu(details.globalPosition),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered ? AppColors.cardHover : AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 12),
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: statusColor),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(fwd.label,
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(width: 8),
                        _Badge(fwd.typeLabel),
                        if (fwd.status == ForwardStatus.active) ...[
                          const SizedBox(width: 6),
                          _Badge('${fwd.activeConnections} conn'),
                        ],
                        if (fwd.status == ForwardStatus.reconnecting) ...[
                          const SizedBox(width: 6),
                          const _Badge('reconnecting…'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(fwd.summary,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 11)),
                    if (fwd.status == ForwardStatus.error &&
                        fwd.errorMessage != null) ...[
                      const SizedBox(height: 2),
                      Text(fwd.errorMessage!,
                          style: const TextStyle(
                              color: AppColors.red, fontSize: 11)),
                    ],
                  ],
                ),
              ),
              _IconAction(
                icon: running ? Icons.stop : Icons.play_arrow,
                color: running ? AppColors.red : AppColors.accent,
                onTap: () {
                  final service = context.read<PortForwardService>();
                  if (running) {
                    service.stop(fwd.id);
                  } else {
                    service.start(fwd);
                  }
                },
              ),
              if (_hovered) ...[
                const SizedBox(width: 6),
                _IconAction(
                  icon: Icons.delete_outlined,
                  color: AppColors.red,
                  onTap: _delete,
                ),
              ],
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
  final VoidCallback onTap;
  const _IconAction(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 14, color: color),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  const _Badge(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: AppColors.border, borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w500)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_horiz,
                size: 52, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            const Text('No rules yet',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            const Text(
                'Create local, remote, or SOCKS5 port forwarding rules',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: onAdd,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(8)),
                child: const Text('+ New Rule',
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Forward Panel ─────────────────────────────────────────

class _ForwardPanel extends StatefulWidget {
  final PortForward? initial;
  final VoidCallback onClose;
  final Future<void> Function(PortForward) onSave;
  const _ForwardPanel(
      {super.key, this.initial, required this.onClose, required this.onSave});

  @override
  State<_ForwardPanel> createState() => _ForwardPanelState();
}

class _ForwardPanelState extends State<_ForwardPanel> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController();
  final _localHost = TextEditingController(text: '127.0.0.1');
  final _localPort = TextEditingController();
  final _remoteHost = TextEditingController();
  final _remotePort = TextEditingController();
  ForwardType _type = ForwardType.local;
  String? _selectedHostId;
  bool _autoStart = false;
  bool _saving = false;

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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(PortForward(
        id: widget.initial?.id,
        label: _label.text.trim(),
        type: _type,
        localHost: _localHost.text.trim(),
        localPort: int.parse(_localPort.text),
        remoteHost: _remoteHost.text.trim(),
        remotePort: int.tryParse(_remotePort.text) ?? 0,
        hostId: _selectedHostId,
        autoStart: _autoStart,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hosts = context.watch<HostProvider>().hosts;
    final isDynamic = _type == ForwardType.dynamic;

    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _field(_label, 'Label',
                      autofocus: true,
                      validator: (v) =>
                          v?.isEmpty == true ? 'Required' : null),
                  const SizedBox(height: 12),
                  _dropdown(),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        flex: 2,
                        child: _field(_localHost, 'Local Host',
                            validator: (v) =>
                                v?.isEmpty == true ? 'Required' : null)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 90,
                      child: _field(_localPort, 'Port',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          validator: (v) =>
                              int.tryParse(v ?? '') == null
                                  ? 'Invalid'
                                  : null),
                    ),
                  ]),
                  if (!isDynamic) ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          flex: 2,
                          child: _field(_remoteHost, 'Remote Host',
                              validator: (v) =>
                                  v?.isEmpty == true ? 'Required' : null)),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 90,
                        child: _field(_remotePort, 'Port',
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            validator: (v) =>
                                int.tryParse(v ?? '') == null
                                    ? 'Invalid'
                                    : null),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: hosts.any((h) => h.id == _selectedHostId)
                        ? _selectedHostId
                        : null,
                    decoration: _inputDecoration('SSH Host (optional)'),
                    hint: const Text('Select host',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 13)),
                    dropdownColor: AppColors.card,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13),
                    items: hosts
                        .map((h) => DropdownMenuItem(
                            value: h.id, child: Text(h.label)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _selectedHostId = v),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => setState(() => _autoStart = !_autoStart),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: _autoStart,
                            activeColor: AppColors.accent,
                            checkColor: Colors.black,
                            onChanged: (v) =>
                                setState(() => _autoStart = v ?? false),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('Auto-start on launch',
                            style: TextStyle(
                                color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _submit,
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.black),
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black))
                          : Text(widget.initial == null ? 'Add Rule' : 'Save',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
                widget.initial == null
                    ? 'New Port Forward Rule'
                    : 'Edit Port Forward Rule',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ),
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.close,
                  size: 14, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown() {
    return DropdownButtonFormField<ForwardType>(
      initialValue: _type,
      decoration: _inputDecoration('Type'),
      dropdownColor: AppColors.card,
      style:
          const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      items: const [
        DropdownMenuItem(value: ForwardType.local, child: Text('Local')),
        DropdownMenuItem(
            value: ForwardType.remote, child: Text('Remote')),
        DropdownMenuItem(
            value: ForwardType.dynamic,
            child: Text('Dynamic SOCKS5')),
      ],
      onChanged: (v) => setState(() => _type = v!),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle:
          const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      filled: true,
      fillColor: AppColors.card,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accent)),
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    bool autofocus = false,
    int? maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      autofocus: autofocus,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style:
          const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      decoration: _inputDecoration(label),
      validator: validator,
    );
  }
}
