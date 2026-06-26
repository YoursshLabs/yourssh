import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/host.dart';
import '../../models/ssh_key.dart';
import '../../providers/host_provider.dart';
import '../../providers/key_provider.dart';
import '../../theme/app_theme.dart';
import '../theme/mobile_tokens.dart';
import '../widgets/section_header.dart';

/// Minimal add/edit host form for mobile: label/host/port/username + password
/// or a saved key. Pass [existing] to edit an existing host (preserving its
/// id, tags, jump chain, and other desktop-only fields); omit it to add a new
/// one. The full editor (tags, proxy, jump chain, RDP/VNC) is desktop-only.
class MobileAddHostScreen extends StatefulWidget {
  /// The host to edit, or null to create a new one.
  final Host? existing;

  const MobileAddHostScreen({super.key, this.existing});

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

  bool get _isEdit => widget.existing != null;

  /// Certificate and agent auth have no UI in this minimal form, so editing
  /// such a host shows a read-only note and preserves the auth untouched.
  bool get _isCertOrAgent {
    final a = widget.existing?.authType;
    return a == AuthType.certificate || a == AuthType.agent;
  }

  @override
  void initState() {
    super.initState();
    final h = widget.existing;
    if (h != null) {
      _label.text = h.label;
      _address.text = h.host;
      _port.text = '${h.port}';
      _username.text = h.username;
      _useKey = h.authType == AuthType.privateKey;
      _keyId = h.keyId;
    }
  }

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

    final port = int.tryParse(_port.text.trim()) ?? 22;
    final authType = _useKey ? AuthType.privateKey : AuthType.password;
    final keyId = _useKey ? _keyId : null;
    final provider = context.read<HostProvider>();
    final existing = widget.existing;

    if (existing != null) {
      // Preserve id, tags, jump chain, and other fields the minimal form
      // doesn't expose; only overwrite what's editable here.
      if (_isCertOrAgent) {
        // Certificate / agent auth isn't editable here (no cert-path / agent
        // UI), so keep authType + keyId exactly as-is — editing connection
        // fields must never silently downgrade it to password.
        await provider.updateHost(existing.copyWith(
          label: label,
          host: address,
          port: port,
          username: username,
        ));
      } else {
        // A blank password leaves the stored one untouched (updateHost skips
        // empty passwords).
        await provider.updateHost(
          existing.copyWith(
            label: label,
            host: address,
            port: port,
            username: username,
            authType: authType,
            keyId: keyId,
          ),
          password: _useKey ? null : _password.text,
        );
      }
    } else {
      final host = Host(
        label: label,
        host: address,
        port: port,
        username: username,
        authType: authType,
        keyId: keyId,
      );
      await provider.addHost(host, password: _useKey ? null : _password.text);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final keys = context.watch<KeyProvider>().keys;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(_isEdit ? 'Edit host' : 'Add host'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SectionHeader('Connection'),
            _field(_label, 'Label', fieldKey: 'host-label'),
            _field(_address, 'Host / IP', fieldKey: 'host-address'),
            _field(_port, 'Port',
                fieldKey: 'host-port',
                keyboard: TextInputType.number,
                formatters: [FilteringTextInputFormatter.digitsOnly]),
            _field(_username, 'Username', fieldKey: 'host-username'),
            const SizedBox(height: MobileTokens.space2),
            const SectionHeader('Authentication'),
            if (_isCertOrAgent)
              _CertAgentNote(authType: widget.existing!.authType)
            else ...[
              SwitchListTile(
                value: _useKey,
                onChanged:
                    keys.isEmpty ? null : (v) => setState(() => _useKey = v),
                title: const Text('Use SSH key',
                    style: TextStyle(color: AppColors.textPrimary)),
                subtitle: keys.isEmpty
                    ? const Text('No keys imported — using password',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12))
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
                    fieldKey: 'host-password',
                    obscure: true,
                    hint: _isEdit ? 'Leave blank to keep current' : null),
            ],
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
    String? hint,
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
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }
}

/// Read-only authentication note shown when editing a certificate- or
/// agent-authenticated host (which the minimal mobile form can't edit). The
/// auth is preserved as-is on save.
class _CertAgentNote extends StatelessWidget {
  final AuthType authType;
  const _CertAgentNote({required this.authType});

  @override
  Widget build(BuildContext context) {
    final kind =
        authType == AuthType.certificate ? 'Certificate' : 'SSH agent';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.verified_user_outlined,
          color: AppColors.textSecondary),
      title: Text('$kind authentication',
          style: const TextStyle(color: AppColors.textPrimary)),
      subtitle: const Text('Configured on desktop — kept unchanged',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
    );
  }
}
