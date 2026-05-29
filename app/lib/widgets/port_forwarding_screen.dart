import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/port_forward.dart';
import '../providers/host_provider.dart';
import '../providers/port_forward_provider.dart';
import '../theme/app_theme.dart';

class PortForwardingScreen extends StatelessWidget {
  const PortForwardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PortForwardProvider>();

    return Container(
      color: AppColors.bg,
      child: Column(
        children: [
          _TopBar(onAdd: () => _showAddDialog(context)),
          Expanded(
            child: provider.forwards.isEmpty
                ? _EmptyState(onAdd: () => _showAddDialog(context))
                : ListView.builder(
                    padding: const EdgeInsets.all(24),
                    itemCount: provider.forwards.length,
                    itemBuilder: (_, i) => _ForwardTile(forward: provider.forwards[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    final result = await showDialog<PortForward>(
      context: context,
      builder: (_) => const _AddForwardDialog(),
    );
    if (result != null && context.mounted) {
      await context.read<PortForwardProvider>().add(result);
    }
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
          const Text('Port Forwarding', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
          const Spacer(),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(6)),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 14, color: Colors.black),
                  SizedBox(width: 6),
                  Text('NEW RULE', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
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
  const _ForwardTile({required this.forward});

  @override
  State<_ForwardTile> createState() => _ForwardTileState();
}

class _ForwardTileState extends State<_ForwardTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final fwd = widget.forward;
    final statusColor = switch (fwd.status) {
      ForwardStatus.active => AppColors.accent,
      ForwardStatus.error => AppColors.red,
      ForwardStatus.idle => AppColors.textTertiary,
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
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
              width: 8, height: 8,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(fwd.label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
                      const SizedBox(width: 8),
                      _Badge(fwd.typeLabel),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(fwd.summary, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            if (_hovered)
              GestureDetector(
                onTap: () => context.read<PortForwardProvider>().delete(fwd.id),
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.delete_outlined, size: 14, color: AppColors.red),
                ),
              ),
          ],
        ),
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
      decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w500)),
    );
  }
}

class _AddForwardDialog extends StatefulWidget {
  const _AddForwardDialog();

  @override
  State<_AddForwardDialog> createState() => _AddForwardDialogState();
}

class _AddForwardDialogState extends State<_AddForwardDialog> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController();
  final _localHost = TextEditingController(text: '127.0.0.1');
  final _localPort = TextEditingController();
  final _remoteHost = TextEditingController();
  final _remotePort = TextEditingController();
  ForwardType _type = ForwardType.local;
  String? _selectedHostId;

  @override
  void dispose() {
    for (final c in [_label, _localHost, _localPort, _remoteHost, _remotePort]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(PortForward(
      label: _label.text.trim(),
      type: _type,
      localHost: _localHost.text.trim(),
      localPort: int.parse(_localPort.text),
      remoteHost: _remoteHost.text.trim(),
      remotePort: int.tryParse(_remotePort.text) ?? 0,
      hostId: _selectedHostId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hosts = context.watch<HostProvider>().hosts;
    final isDynamic = _type == ForwardType.dynamic;

    return AlertDialog(
      title: const Text('New Port Forward Rule'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(labelText: 'Label', border: OutlineInputBorder()),
                validator: (v) => v?.isEmpty == true ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ForwardType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: ForwardType.local, child: Text('Local')),
                  DropdownMenuItem(value: ForwardType.remote, child: Text('Remote')),
                  DropdownMenuItem(value: ForwardType.dynamic, child: Text('Dynamic SOCKS5')),
                ],
                onChanged: (v) => setState(() => _type = v!),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(flex: 2, child: TextFormField(
                  controller: _localHost,
                  decoration: const InputDecoration(labelText: 'Local Host', border: OutlineInputBorder()),
                  validator: (v) => v?.isEmpty == true ? 'Required' : null,
                )),
                const SizedBox(width: 8),
                SizedBox(width: 90, child: TextFormField(
                  controller: _localPort,
                  decoration: const InputDecoration(labelText: 'Local Port', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) => int.tryParse(v ?? '') == null ? 'Invalid' : null,
                )),
              ]),
              if (!isDynamic) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(flex: 2, child: TextFormField(
                    controller: _remoteHost,
                    decoration: const InputDecoration(labelText: 'Remote Host', border: OutlineInputBorder()),
                    validator: (v) => v?.isEmpty == true ? 'Required' : null,
                  )),
                  const SizedBox(width: 8),
                  SizedBox(width: 90, child: TextFormField(
                    controller: _remotePort,
                    decoration: const InputDecoration(labelText: 'Remote Port', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) => int.tryParse(v ?? '') == null ? 'Invalid' : null,
                  )),
                ]),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedHostId,
                decoration: const InputDecoration(labelText: 'SSH Host (optional)', border: OutlineInputBorder()),
                hint: const Text('Select host'),
                items: hosts.map((h) => DropdownMenuItem(value: h.id, child: Text(h.label))).toList(),
                onChanged: (v) => setState(() => _selectedHostId = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
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
            const Icon(Icons.swap_horiz, size: 52, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            const Text('No rules yet', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            const Text('Create local, remote, or SOCKS5 port forwarding rules', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: onAdd,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8)),
                child: const Text('+ New Rule', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
