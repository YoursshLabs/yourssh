import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../providers/key_provider.dart';

class AddHostDialog extends StatefulWidget {
  final Host? existing;
  const AddHostDialog({super.key, this.existing});

  @override
  State<AddHostDialog> createState() => _AddHostDialogState();
}

class _AddHostDialogState extends State<AddHostDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late AuthType _authType;
  String? _selectedKeyId;

  @override
  void initState() {
    super.initState();
    final h = widget.existing;
    _label = TextEditingController(text: h?.label ?? '');
    _host = TextEditingController(text: h?.host ?? '');
    _port = TextEditingController(text: (h?.port ?? 22).toString());
    _username = TextEditingController(text: h?.username ?? '');
    _password = TextEditingController();
    _authType = h?.authType ?? AuthType.password;
    _selectedKeyId = h?.keyId;
  }

  @override
  void dispose() {
    for (final c in [_label, _host, _port, _username, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final host = Host(
      id: widget.existing?.id,
      label: _label.text.trim(),
      host: _host.text.trim(),
      port: int.tryParse(_port.text) ?? 22,
      username: _username.text.trim(),
      authType: _authType,
      keyId: (_authType == AuthType.privateKey || _authType == AuthType.certificate)
          ? _selectedKeyId
          : null,
    );
    Navigator.of(context).pop((host: host, password: _password.text));
  }

  @override
  Widget build(BuildContext context) {
    final keys = context.watch<KeyProvider>().keys;

    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Host' : 'Edit Host'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(_label, 'Label', hint: 'My Server'),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(flex: 3, child: _field(_host, 'Host / IP', hint: '192.168.1.1')),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: TextFormField(
                    controller: _port,
                    decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) => (int.tryParse(v ?? '') == null) ? 'Invalid' : null,
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              _field(_username, 'Username', hint: 'root'),
              const SizedBox(height: 12),
              DropdownButtonFormField<AuthType>(
                initialValue: _authType,
                decoration: const InputDecoration(labelText: 'Auth Method', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: AuthType.password, child: Text('Password')),
                  DropdownMenuItem(value: AuthType.privateKey, child: Text('Private Key')),
                  DropdownMenuItem(value: AuthType.certificate, child: Text('Certificate (Key + CA cert)')),
                  DropdownMenuItem(value: AuthType.agent, child: Text('SSH Agent')),
                ],
                onChanged: (v) => setState(() { _authType = v!; _selectedKeyId = null; }),
              ),
              if (_authType == AuthType.password) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    helperText: 'Stored securely in system keychain',
                  ),
                ),
              ],
              if (_authType == AuthType.privateKey) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedKeyId,
                  decoration: const InputDecoration(labelText: 'SSH Key', border: OutlineInputBorder()),
                  hint: const Text('Select a key'),
                  items: keys.map((k) => DropdownMenuItem(
                    value: k.id,
                    child: Text('${k.label} (${k.algorithmLabel})'),
                  )).toList(),
                  onChanged: (v) => setState(() => _selectedKeyId = v),
                  validator: (v) => v == null ? 'Select a key' : null,
                ),
              ],
              if (_authType == AuthType.certificate) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedKeyId,
                  decoration: const InputDecoration(
                    labelText: 'SSH Key (with linked certificate)',
                    border: OutlineInputBorder(),
                  ),
                  hint: const Text('Select a key'),
                  items: keys.map((k) => DropdownMenuItem(
                    value: k.id,
                    child: Row(
                      children: [
                        Text('${k.label} (${k.algorithmLabel})'),
                        if (k.hasCertificate) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text('CERT',
                                style: TextStyle(
                                    color: Colors.green,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                  )).toList(),
                  onChanged: (v) => setState(() => _selectedKeyId = v),
                  validator: (v) {
                    if (v == null) return 'Select a key';
                    final key = keys.where((k) => k.id == v).firstOrNull;
                    if (key == null || !key.hasCertificate) {
                      return 'Selected key has no linked certificate. Add one in Keychain.';
                    }
                    return null;
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.existing == null ? 'Add' : 'Save')),
      ],
    );
  }

  Widget _field(TextEditingController ctrl, String label, {String? hint}) =>
      TextFormField(
        controller: ctrl,
        decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
      );
}
