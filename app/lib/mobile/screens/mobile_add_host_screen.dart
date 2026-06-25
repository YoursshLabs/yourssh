import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/host.dart';
import '../../models/ssh_key.dart';
import '../../providers/host_provider.dart';
import '../../providers/key_provider.dart';
import '../../theme/app_theme.dart';

/// Minimal add-host form for mobile: label/host/port/username + password or a
/// saved key. The full editor (tags, proxy, jump chain, RDP/VNC) is
/// desktop-only.
class MobileAddHostScreen extends StatefulWidget {
  const MobileAddHostScreen({super.key});

  @override
  State<MobileAddHostScreen> createState() => _MobileAddHostScreenState();
}

class _MobileAddHostScreenState extends State<MobileAddHostScreen> {
  final _label = TextEditingController();
  final _address = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _useKey = false;
  String? _keyId;

  @override
  void dispose() {
    for (final c in [_label, _address, _port, _username, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    final address = _address.text.trim();
    final username = _username.text.trim();
    if (label.isEmpty || address.isEmpty || username.isEmpty) return;

    final host = Host(
      label: label,
      host: address,
      port: int.tryParse(_port.text.trim()) ?? 22,
      username: username,
      authType: _useKey ? AuthType.privateKey : AuthType.password,
      keyId: _useKey ? _keyId : null,
    );
    await context.read<HostProvider>().addHost(
          host,
          password: _useKey ? null : _password.text,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final keys = context.watch<KeyProvider>().keys;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('Add host'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field(_label, 'Label', fieldKey: 'host-label'),
            _field(_address, 'Host / IP', fieldKey: 'host-address'),
            _field(_port, 'Port',
                fieldKey: 'host-port',
                keyboard: TextInputType.number,
                formatters: [FilteringTextInputFormatter.digitsOnly]),
            _field(_username, 'Username', fieldKey: 'host-username'),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _useKey,
              onChanged:
                  keys.isEmpty ? null : (v) => setState(() => _useKey = v),
              title: const Text('Use SSH key',
                  style: TextStyle(color: AppColors.textPrimary)),
              subtitle: keys.isEmpty
                  ? const Text('No keys imported — using password',
                      style:
                          TextStyle(color: AppColors.textSecondary, fontSize: 12))
                  : null,
            ),
            if (_useKey)
              DropdownButtonFormField<String>(
                initialValue: _keyId,
                items: [
                  for (final SshKeyEntry k in keys)
                    DropdownMenuItem(value: k.id, child: Text(k.label)),
                ],
                onChanged: (v) => setState(() => _keyId = v),
                decoration: const InputDecoration(labelText: 'Key'),
              )
            else
              _field(_password, 'Password',
                  fieldKey: 'host-password', obscure: true),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    required String fieldKey,
    bool obscure = false,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        key: Key(fieldKey),
        controller: c,
        obscureText: obscure,
        keyboardType: keyboard,
        inputFormatters: formatters,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}
