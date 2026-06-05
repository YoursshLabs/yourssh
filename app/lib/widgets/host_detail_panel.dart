import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../providers/host_provider.dart';
import '../providers/key_provider.dart';
import '../services/ssh_service.dart';
import '../theme/app_theme.dart';

class HostDetailPanel extends StatefulWidget {
  final Host? existing;
  final String? initialGroup;
  final VoidCallback onClose;
  final Future<void> Function(Host host, String password) onSave;
  final Future<void> Function(Host host)? onConnect;

  const HostDetailPanel({
    super.key,
    this.existing,
    this.initialGroup,
    required this.onClose,
    required this.onSave,
    this.onConnect,
  });

  @override
  State<HostDetailPanel> createState() => _HostDetailPanelState();
}

class _HostDetailPanelState extends State<HostDetailPanel> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _hostCtrl;
  late final TextEditingController _labelCtrl;
  late final TextEditingController _groupCtrl;
  late final TextEditingController _tagsCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _passwordCtrl;
  late AuthType _authType;
  String? _selectedKeyId;
  bool _obscurePassword = true;
  bool _saving = false;
  bool _testing = false;
  ({bool success, int latencyMs, String? error})? _testResult;
  bool _autoRecord = false;
  bool _shellIntegration = true;
  bool _agentForwarding = false;
  String? _selectedJumpHostId;
  late SftpMode _sftpMode;
  late final TextEditingController _sftpCommand;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final h = widget.existing;
    _hostCtrl = TextEditingController(text: h?.host ?? '');
    _labelCtrl = TextEditingController(text: h?.label ?? '');
    _groupCtrl = TextEditingController(text: h?.group ?? widget.initialGroup ?? '');
    _tagsCtrl = TextEditingController(text: h?.tags.join(', ') ?? '');
    _portCtrl = TextEditingController(text: (h?.port ?? 22).toString());
    _usernameCtrl = TextEditingController(text: h?.username ?? '');
    _passwordCtrl = TextEditingController();
    _authType = h?.authType ?? AuthType.password;
    _selectedKeyId = h?.keyId;
    _autoRecord = h?.autoRecord ?? false;
    _shellIntegration = h?.shellIntegration ?? true;
    _agentForwarding = h?.agentForwarding ?? false;
    _selectedJumpHostId = h?.jumpHostId;
    _sftpMode = h?.sftpMode ?? SftpMode.normal;
    _sftpCommand = TextEditingController(text: h?.sftpServerCommand ?? '');
    for (final c in [_hostCtrl, _portCtrl, _usernameCtrl, _passwordCtrl]) {
      c.addListener(_clearTestResult);
    }
  }

  void _clearTestResult() {
    if (_testResult != null || _testing) setState(() { _testResult = null; _testing = false; });
  }

  @override
  void dispose() {
    for (final c in [_hostCtrl, _labelCtrl, _groupCtrl, _tagsCtrl, _portCtrl, _usernameCtrl, _passwordCtrl, _sftpCommand]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final tags = _tagsCtrl.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    final host = Host(
      id: widget.existing?.id,
      label: _labelCtrl.text.trim().isEmpty ? _hostCtrl.text.trim() : _labelCtrl.text.trim(),
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text) ?? 22,
      username: _usernameCtrl.text.trim(),
      authType: _authType,
      keyId: _authType == AuthType.privateKey ? _selectedKeyId : null,
      group: _groupCtrl.text.trim(),
      tags: tags,
      autoRecord: _autoRecord,
      shellIntegration: _shellIntegration,
      agentForwarding: _agentForwarding,
      jumpHostId: _selectedJumpHostId,
      sftpMode: _sftpMode,
      sftpServerCommand:
          _sftpMode == SftpMode.custom ? _sftpCommand.text.trim() : null,
    );
    try {
      await widget.onSave(host, _passwordCtrl.text);
      if (mounted) widget.onClose();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _connect() async {
    if (_formKey.currentState?.validate() != true) return;
    await _save();
  }

  Future<void> _test() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() { _testing = true; _testResult = null; });

    final keys = context.read<KeyProvider>().keys;
    final keyEntry = _authType == AuthType.privateKey && _selectedKeyId != null
        ? keys.where((k) => k.id == _selectedKeyId).firstOrNull
        : null;

    final allHosts = context.read<HostProvider>().allHosts;
    Host? jumpHost;
    if (_selectedJumpHostId != null) {
      jumpHost = allHosts.where((h) => h.id == _selectedJumpHostId).firstOrNull;
    }
    final jumpKeyEntry = (jumpHost != null && jumpHost.keyId != null)
        ? context.read<KeyProvider>().findById(jumpHost.keyId!)
        : null;

    final host = Host(
      id: widget.existing?.id,
      label: _hostCtrl.text.trim(),
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text) ?? 22,
      username: _usernameCtrl.text.trim(),
      authType: _authType,
      keyId: _authType == AuthType.privateKey ? _selectedKeyId : null,
      group: '',
      tags: const [],
      jumpHostId: _selectedJumpHostId,
      sftpMode: _sftpMode,
      sftpServerCommand:
          _sftpMode == SftpMode.custom ? _sftpCommand.text.trim() : null,
    );

    final result = await context.read<SshService>().testConnection(
      host,
      password: _passwordCtrl.text,
      keyEntry: keyEntry,
      jumpHost: jumpHost,
      jumpKeyEntry: jumpKeyEntry,
    );

    if (mounted) setState(() { _testing = false; _testResult = result; });
  }

  @override
  Widget build(BuildContext context) {
    final keys = context.watch<KeyProvider>().keys;

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
                  // Address card
                  _Card(children: [
                    _AddressField(controller: _hostCtrl),
                  ]),

                  const SizedBox(height: 16),
                  _sectionLabel('GENERAL'),
                  const SizedBox(height: 6),
                  _Card(children: [
                    _PanelField(
                      controller: _labelCtrl,
                      hint: 'Label',
                      icon: Icons.label_outline,
                    ),
                    _divider(),
                    _PanelField(
                      controller: _groupCtrl,
                      hint: 'Group',
                      icon: Icons.folder_outlined,
                    ),
                    _divider(),
                    _PanelField(
                      controller: _tagsCtrl,
                      hint: 'Tags, e.g. env:prod, role:db',
                      icon: Icons.tag,
                    ),
                  ]),

                  const SizedBox(height: 16),
                  // SSH Port row
                  Row(
                    children: [
                      const Text('SSH on', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 56,
                        child: TextFormField(
                          controller: _portCtrl,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            filled: true,
                            fillColor: AppColors.card,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(color: AppColors.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(color: AppColors.border),
                            ),
                          ),
                          validator: (v) => int.tryParse(v ?? '') == null ? '!' : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text('port', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),

                  const SizedBox(height: 16),
                  _sectionLabel('CREDENTIALS'),
                  const SizedBox(height: 6),
                  _Card(children: [
                    _PanelField(
                      controller: _usernameCtrl,
                      hint: 'Username',
                      icon: Icons.person_outline,
                    ),
                    _divider(),
                    _PasswordField(
                      controller: _passwordCtrl,
                      obscure: _obscurePassword,
                      onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ]),

                  const SizedBox(height: 16),
                  _sectionLabel('AUTH METHOD'),
                  const SizedBox(height: 6),
                  _Card(children: [
                    _DropdownRow(
                      icon: Icons.lock_outline,
                      child: DropdownButton<AuthType>(
                        value: _authType,
                        isExpanded: true,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                        dropdownColor: AppColors.card,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: AuthType.password, child: Text('Password')),
                          DropdownMenuItem(value: AuthType.privateKey, child: Text('Private Key')),
                          DropdownMenuItem(value: AuthType.agent, child: Text('SSH Agent')),
                        ],
                        onChanged: (v) => setState(() { _authType = v!; _selectedKeyId = null; _testResult = null; }),
                      ),
                    ),
                    if (_authType == AuthType.privateKey) ...[
                      _divider(),
                      _DropdownRow(
                        icon: Icons.vpn_key_outlined,
                        child: DropdownButton<String>(
                          value: _selectedKeyId,
                          isExpanded: true,
                          hint: const Text('Select key', style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                          dropdownColor: AppColors.card,
                          underline: const SizedBox(),
                          items: keys.map((k) => DropdownMenuItem(
                            value: k.id,
                            child: Text('${k.label} (${k.algorithmLabel})'),
                          )).toList(),
                          onChanged: (v) => setState(() { _selectedKeyId = v; _testResult = null; }),
                        ),
                      ),
                    ],
                  ]),

                  const SizedBox(height: 16),
                  _sectionLabel('JUMP HOST'),
                  const SizedBox(height: 6),
                  Builder(builder: (context) {
                    final allHosts = context.watch<HostProvider>().allHosts;
                    final existingId = widget.existing?.id;
                    final otherHosts = allHosts
                        .where((h) => h.id != existingId)
                        .toList();
                    if (otherHosts.isEmpty) return const SizedBox.shrink();
                    // Drop a stale jump host selection if that host was deleted
                    // — otherwise DropdownButton asserts on a value not in items.
                    final validJump = _selectedJumpHostId != null &&
                            otherHosts.any((h) => h.id == _selectedJumpHostId)
                        ? _selectedJumpHostId
                        : null;
                    if (validJump != _selectedJumpHostId) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _selectedJumpHostId = validJump);
                      });
                    }
                    return _Card(children: [
                      _DropdownRow(
                        icon: Icons.hive_outlined,
                        child: DropdownButton<String?>(
                          value: validJump,
                          isExpanded: true,
                          hint: const Text(
                            'None (direct connection)',
                            style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                          ),
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                          dropdownColor: AppColors.card,
                          underline: const SizedBox(),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('None (direct connection)',
                                  style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
                            ),
                            ...otherHosts.map((h) => DropdownMenuItem<String?>(
                              value: h.id,
                              child: Text(
                                '${h.label} (${h.username}@${h.host})',
                                style: const TextStyle(fontSize: 13),
                              ),
                            )),
                          ],
                          onChanged: (v) => setState(() => _selectedJumpHostId = v),
                        ),
                      ),
                    ]);
                  }),

                  const SizedBox(height: 16),
                  _sectionLabel('SFTP MODE'),
                  const SizedBox(height: 6),
                  _Card(children: [
                    _DropdownRow(
                      icon: Icons.admin_panel_settings_outlined,
                      child: DropdownButton<SftpMode>(
                        value: _sftpMode,
                        isExpanded: true,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                        dropdownColor: AppColors.card,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: SftpMode.normal, child: Text('Default')),
                          DropdownMenuItem(value: SftpMode.sudo, child: Text('Sudo (root)')),
                          DropdownMenuItem(value: SftpMode.custom, child: Text('Custom command')),
                        ],
                        onChanged: (v) => setState(() => _sftpMode = v!),
                      ),
                    ),
                    if (_sftpMode == SftpMode.custom) ...[
                      _divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.terminal, size: 16, color: AppColors.textTertiary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: _sftpCommand,
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                                decoration: const InputDecoration(
                                  hintText: 'sudo /usr/lib/openssh/sftp-server',
                                  hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                validator: (v) => _sftpMode == SftpMode.custom &&
                                        (v == null || v.trim().isEmpty)
                                    ? 'Required'
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ]),

                  const SizedBox(height: 16),
                  _sectionLabel('SESSION'),
                  const SizedBox(height: 6),
                  _Card(children: [
                    SwitchListTile(
                      value: _autoRecord,
                      onChanged: (v) => setState(() => _autoRecord = v),
                      title: const Text(
                        'Auto-record sessions',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      ),
                      subtitle: const Text(
                        'Start recording automatically on connect',
                        style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                      ),
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      activeThumbColor: AppColors.accent,
                    ),
                    SwitchListTile(
                      value: _shellIntegration,
                      onChanged: (v) => setState(() => _shellIntegration = v),
                      title: const Text(
                        'Shell integration',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      ),
                      subtitle: const Text(
                        'cwd, command status & path completion on bash/zsh',
                        style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                      ),
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      activeThumbColor: AppColors.accent,
                    ),
                    SwitchListTile(
                      value: _agentForwarding,
                      onChanged: (v) => setState(() => _agentForwarding = v),
                      title: const Text(
                        'Agent forwarding',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      ),
                      subtitle: const Text(
                        'Forward your local SSH agent to this host (like ssh -A). '
                        'Applies on next connect.',
                        style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                      ),
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      activeThumbColor: AppColors.accent,
                    ),
                  ]),

                  const SizedBox(height: 24),
                  // Test connection button
                  GestureDetector(
                    onTap: (_testing || _saving) ? null : _test,
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      alignment: Alignment.center,
                      child: _testing
                          ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.textSecondary)),
                                SizedBox(width: 8),
                                Text('TESTING…', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, letterSpacing: 0.5)),
                              ],
                            )
                          : const Text('TEST CONNECTION', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, letterSpacing: 0.5)),
                    ),
                  ),
                  if (_testResult != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _testResult!.success
                            ? AppColors.accent.withValues(alpha: 0.08)
                            : AppColors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _testResult!.success
                              ? AppColors.accent.withValues(alpha: 0.3)
                              : AppColors.red.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _testResult!.success ? Icons.check_circle_outline : Icons.error_outline,
                            size: 14,
                            color: _testResult!.success ? AppColors.accent : AppColors.red,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _testResult!.success
                                  ? 'Connected · ${_testResult!.latencyMs}ms'
                                  : _testResult!.error ?? 'Failed',
                              style: TextStyle(
                                color: _testResult!.success ? AppColors.accent : AppColors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  // Connect button
                  GestureDetector(
                    onTap: _saving ? null : _connect,
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: _saving ? AppColors.accentDim : AppColors.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                          : const Text('CONNECT', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 1)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Save without connecting
                  GestureDetector(
                    onTap: _saving ? null : _save,
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      alignment: Alignment.center,
                      child: const Text('SAVE ONLY', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, letterSpacing: 0.5)),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _isNew ? 'New Host' : 'Edit Host',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.close, size: 14, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(label, style: const TextStyle(color: AppColors.textTertiary, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.8));
  }

  Widget _divider() => const Divider(height: 1, color: AppColors.border, indent: 36);
}

// ── Sub-widgets ───────────────────────────────────────────

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    // Material (not Container) so descendant ListTiles find a Material
    // ancestor with a color — a plain DecoratedBox trips Flutter's "ListTile
    // background color or ink splashes may be invisible" assertion in tests.
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _AddressField extends StatelessWidget {
  final TextEditingController controller;
  const _AddressField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.blue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.dns, color: AppColors.blue, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                hintText: 'IP or Hostname',
                hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  const _PanelField({required this.controller, required this.hint, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: controller,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              validator: null,
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;
  const _PasswordField({required this.controller, required this.obscure, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.password, size: 16, color: AppColors.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: TextFormField(
              controller: controller,
              obscureText: obscure,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Password',
                hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          GestureDetector(
            onTap: onToggle,
            child: Icon(
              obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _DropdownRow extends StatelessWidget {
  final IconData icon;
  final Widget child;
  const _DropdownRow({required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textTertiary),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}
