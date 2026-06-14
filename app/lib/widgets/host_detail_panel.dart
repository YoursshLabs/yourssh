import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../providers/host_provider.dart';
import '../providers/key_provider.dart';
import '../providers/settings_provider.dart' show kTermTypes;
import '../services/agent_probe.dart';
import '../services/shell_integration_service.dart';
import '../services/ssh_service.dart';
import '../theme/app_theme.dart';
import '../theme/terminal_themes.dart';
import 'agent_status_line.dart';
import 'host_chain_editor.dart';
import 'network_discovery_sheet.dart';
import 'rdp_badge.dart';
import 'terminal_appearance_controls.dart' show kBundledTerminalFonts;

class HostDetailPanel extends StatefulWidget {
  final Host? existing;
  final String? initialGroup;
  final String? initialHost;
  final int? initialPort;
  final String? initialLabel;
  final HostProtocol? initialProtocol;
  final VoidCallback onClose;
  final Future<void> Function(Host host, String password) onSave;
  final Future<void> Function(Host host)? onConnect;

  /// Test seam for the agent status line; defaults to the real probe using
  /// SshService's Keychain loader.
  final Future<AgentProbeResult> Function()? agentProbe;

  const HostDetailPanel({
    super.key,
    this.existing,
    this.initialGroup,
    this.initialHost,
    this.initialPort,
    this.initialLabel,
    this.initialProtocol,
    required this.onClose,
    required this.onSave,
    this.onConnect,
    this.agentProbe,
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
  bool _recordingRedaction = true;
  bool _shellIntegration = true;
  bool _agentForwarding = false;
  bool _osc52Clipboard = false;
  late final TextEditingController _workingDirCtrl;
  late final TextEditingController _startupSnippetCtrl;
  late final TextEditingController _fontSizeCtrl;
  final List<({TextEditingController key, TextEditingController value})>
      _envRows = [];
  String? _templateTheme;
  String? _templateFont;
  String? _templateTermType;
  bool? _tmuxOverride;
  List<String> _jumpHostIds = [];
  late SftpMode _sftpMode;
  late final TextEditingController _sftpCommand;
  late HostProtocol _protocol;
  late final TextEditingController _domainCtrl;
  late RdpSecurityMode _rdpSecurity;

  bool get _isNew => widget.existing == null;
  bool get _isRdp => _protocol == HostProtocol.rdp;

  @override
  void initState() {
    super.initState();
    final h = widget.existing;
    _protocol = h?.protocol ?? widget.initialProtocol ?? HostProtocol.ssh;
    _domainCtrl = TextEditingController(text: h?.domain ?? '');
    _rdpSecurity = h?.rdpSecurity ?? RdpSecurityMode.auto;
    _hostCtrl = TextEditingController(text: h?.host ?? widget.initialHost ?? '');
    _labelCtrl = TextEditingController(text: h?.label ?? widget.initialLabel ?? '');
    _groupCtrl = TextEditingController(text: h?.group ?? widget.initialGroup ?? '');
    _tagsCtrl = TextEditingController(text: h?.tags.join(', ') ?? '');
    _portCtrl = TextEditingController(
        text: (h?.port ?? widget.initialPort ?? _protocol.defaultPort).toString());
    _usernameCtrl = TextEditingController(text: h?.username ?? '');
    _passwordCtrl = TextEditingController();
    _authType = h?.authType ?? AuthType.password;
    _selectedKeyId = h?.keyId;
    _autoRecord = h?.autoRecord ?? false;
    _recordingRedaction = h?.recordingRedaction ?? true;
    _shellIntegration = h?.shellIntegration ?? true;
    _agentForwarding = h?.agentForwarding ?? false;
    _osc52Clipboard = h?.osc52Clipboard ?? false;
    _workingDirCtrl = TextEditingController(text: h?.workingDir ?? '');
    _startupSnippetCtrl = TextEditingController(text: h?.startupSnippet ?? '');
    _fontSizeCtrl = TextEditingController(text: _fmtFontSize(h?.fontSize));
    for (final e in (h?.envVars ?? const <String, String>{}).entries) {
      _envRows.add((
        key: TextEditingController(text: e.key),
        value: TextEditingController(text: e.value),
      ));
    }
    _templateTheme = h?.terminalThemeId;
    _templateFont = h?.fontFamily;
    _templateTermType = h?.termType;
    _tmuxOverride = h?.tmuxOverride;
    _jumpHostIds = List.of(h?.jumpHostIds ?? const []);
    _sftpMode = h?.sftpMode ?? SftpMode.normal;
    _sftpCommand = TextEditingController(text: h?.sftpServerCommand ?? '');
    for (final c in [_hostCtrl, _portCtrl, _usernameCtrl, _passwordCtrl]) {
      c.addListener(_clearTestResult);
    }
    if (h != null && _authType == AuthType.password) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadExistingPassword(h.id));
    }
  }

  Future<void> _loadExistingPassword(String hostId) async {
    if (!mounted) return;
    final pw = await context.read<SshService>().loadPassword(hostId);
    if (mounted && pw != null && pw.isNotEmpty && _passwordCtrl.text.isEmpty) {
      setState(() => _passwordCtrl.text = pw);
    }
  }

  void _clearTestResult() {
    if (_testResult != null || _testing) setState(() { _testResult = null; _testing = false; });
  }

  /// Display label for the host being edited, used by the chain editor.
  /// Falls back to user@host while the label field is still empty.
  String _currentHostLabel() {
    final label = _labelCtrl.text.trim();
    if (label.isNotEmpty) return label;
    final host = _hostCtrl.text.trim();
    if (host.isEmpty) return 'this host';
    final user = _usernameCtrl.text.trim();
    return user.isEmpty ? host : '$user@$host';
  }

  Future<AgentProbeResult> _probeAgent() {
    final custom = widget.agentProbe;
    if (custom != null) return custom();
    // Defensive: the status line probes from its initState; if this panel is
    // torn down in the same frame, context.read would throw on a dead element.
    if (!mounted) return Future.value(const AgentProbeNothing());
    final loader = context.read<SshService>().keychainIdentitiesLoader;
    return probeAgentStatus(
        loadKeychainIdentities: loader ?? () async => const []);
  }

  static String _fmtFontSize(double? v) => v == null
      ? ''
      : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  /// Switching protocol flips the port only when it still holds the OTHER
  /// protocol's default — a custom port the user typed is preserved.
  void _onProtocolChanged(HostProtocol next) {
    if (next == _protocol) return;
    setState(() {
      final old = _protocol;
      _protocol = next;
      if (int.tryParse(_portCtrl.text) == old.defaultPort) {
        _portCtrl.text = next.defaultPort.toString();
      }
      if (next == HostProtocol.rdp) {
        // RDP supports password auth only.
        _authType = AuthType.password;
        _selectedKeyId = null;
      }
      _testResult = null;
    });
  }

  @override
  void dispose() {
    for (final c in [
      _hostCtrl, _labelCtrl, _groupCtrl, _tagsCtrl, _portCtrl, _usernameCtrl,
      _passwordCtrl, _sftpCommand, _workingDirCtrl, _startupSnippetCtrl,
      _fontSizeCtrl, _domainCtrl,
    ]) {
      c.dispose();
    }
    for (final r in _envRows) {
      r.key.dispose();
      r.value.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final tags = _tagsCtrl.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    final host = Host(
      id: widget.existing?.id,
      createdAt: widget.existing?.createdAt,
      label: _labelCtrl.text.trim().isEmpty ? _hostCtrl.text.trim() : _labelCtrl.text.trim(),
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text) ?? _protocol.defaultPort,
      username: _usernameCtrl.text.trim(),
      protocol: _protocol,
      domain: _isRdp && _domainCtrl.text.trim().isNotEmpty
          ? _domainCtrl.text.trim()
          : null,
      rdpSecurity: _rdpSecurity,
      authType: _isRdp ? AuthType.password : _authType,
      keyId: !_isRdp && _authType == AuthType.privateKey ? _selectedKeyId : null,
      group: _groupCtrl.text.trim(),
      tags: tags,
      autoRecord: !_isRdp && _autoRecord,
      recordingRedaction: _recordingRedaction,
      shellIntegration: _shellIntegration,
      agentForwarding: !_isRdp && _agentForwarding,
      osc52Clipboard: !_isRdp && _osc52Clipboard,
      jumpHostIds: _jumpHostIds,
      sftpMode: _isRdp ? SftpMode.normal : _sftpMode,
      sftpServerCommand: !_isRdp && _sftpMode == SftpMode.custom
          ? _sftpCommand.text.trim()
          : null,
      workingDir: _workingDirCtrl.text.trim().isEmpty
          ? null
          : _workingDirCtrl.text.trim(),
      envVars: {
        for (final r in _envRows)
          if (r.key.text.trim().isNotEmpty) r.key.text.trim(): r.value.text,
      },
      startupSnippet: _startupSnippetCtrl.text.trim().isEmpty
          ? null
          : _startupSnippetCtrl.text,
      terminalThemeId: _templateTheme,
      fontFamily: _templateFont,
      fontSize: double.tryParse(_fontSizeCtrl.text.trim()),
      termType: _templateTermType,
      tmuxOverride: _tmuxOverride,
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
    final keyProvider = context.read<KeyProvider>();
    final jumpChain = <JumpHop>[];
    for (final jid in _jumpHostIds) {
      final jh = allHosts.where((h) => h.id == jid).firstOrNull;
      if (jh == null) continue; // stale id pruned by the editor below
      final jk = jh.keyId == null ? null : keyProvider.findById(jh.keyId!);
      jumpChain.add((host: jh, keyEntry: jk));
    }

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
      jumpHostIds: _jumpHostIds,
      sftpMode: _sftpMode,
      sftpServerCommand:
          _sftpMode == SftpMode.custom ? _sftpCommand.text.trim() : null,
    );

    final result = await context.read<SshService>().testConnection(
      host,
      password: _passwordCtrl.text,
      keyEntry: keyEntry,
      jumpChain: jumpChain,
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
                  // Protocol selector
                  SegmentedButton<HostProtocol>(
                    segments: const [
                      ButtonSegment(
                        value: HostProtocol.ssh,
                        label: Text('SSH'),
                        icon: Icon(Icons.terminal, size: 14),
                      ),
                      ButtonSegment(
                        value: HostProtocol.rdp,
                        label: Text('RDP'),
                        icon: Icon(Icons.desktop_windows_outlined, size: 14),
                      ),
                    ],
                    selected: {_protocol},
                    onSelectionChanged: (s) => _onProtocolChanged(s.first),
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle: WidgetStateProperty.all(const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                      // Selected segment renders on the accent fill — use
                      // black like the CONNECT button (green-on-green text
                      // would be invisible).
                      foregroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? Colors.black
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  // Address card
                  _Card(children: [
                    _AddressField(controller: _hostCtrl),
                  ]),
                  if (_isNew) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.wifi_find, size: 13),
                        label: const Text('Scan network to pick a device',
                            style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                        ),
                        onPressed: () => NetworkDiscoverySheet.show(
                          context,
                          selectionMode: true,
                          onSelected: (h) {
                            setState(() {
                              _hostCtrl.text = h.ip;
                              _portCtrl.text = (h.isRdp
                                      ? 3389
                                      : (h.openPorts.contains(22)
                                          ? 22
                                          : h.openPorts.first))
                                  .toString();
                              if (h.hostname != null &&
                                  _labelCtrl.text.isEmpty) {
                                _labelCtrl.text = h.hostname!;
                              }
                              if (h.isRdp &&
                                  _protocol != HostProtocol.rdp) {
                                _onProtocolChanged(HostProtocol.rdp);
                              }
                            });
                          },
                        ),
                      ),
                    ),
                  ],

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
                  // Port row
                  Row(
                    children: [
                      Text(_isRdp ? 'RDP on' : 'SSH on', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
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
                    if (_isRdp) ...[
                      _divider(),
                      _PanelField(
                        controller: _domainCtrl,
                        hint: 'Domain (optional)',
                        icon: Icons.domain,
                      ),
                    ],
                  ]),

                  if (_isRdp) ...[
                    const SizedBox(height: 16),
                    _sectionLabel('RDP SECURITY'),
                    const SizedBox(height: 6),
                    _Card(children: [
                      _DropdownRow(
                        icon: Icons.security,
                        child: DropdownButton<RdpSecurityMode>(
                          value: _rdpSecurity,
                          isExpanded: true,
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 13),
                          dropdownColor: AppColors.card,
                          underline: const SizedBox(),
                          items: const [
                            DropdownMenuItem(
                                value: RdpSecurityMode.auto,
                                child: Text('Auto (negotiate)')),
                            DropdownMenuItem(
                                value: RdpSecurityMode.nla,
                                child: Text('NLA (CredSSP)')),
                            DropdownMenuItem(
                                value: RdpSecurityMode.tls,
                                child: Text('TLS only')),
                          ],
                          onChanged: (v) =>
                              setState(() => _rdpSecurity = v!),
                        ),
                      ),
                    ]),

                    Builder(builder: (context) {
                      final sshHosts = context
                          .watch<HostProvider>()
                          .allHosts
                          .where((h) =>
                              h.protocol == HostProtocol.ssh &&
                              h.id != widget.existing?.id)
                          .toList();
                      if (sshHosts.isEmpty) return const SizedBox.shrink();
                      // A deleted bastion leaves a stale id — show "direct"
                      // instead of tripping the dropdown's value assert.
                      final current = _jumpHostIds.firstOrNull;
                      final valid =
                          sshHosts.any((h) => h.id == current) ? current : null;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 16),
                          _sectionLabel('SSH TUNNEL'),
                          const SizedBox(height: 6),
                          _Card(children: [
                            _DropdownRow(
                              icon: Icons.alt_route,
                              child: DropdownButton<String?>(
                                value: valid,
                                isExpanded: true,
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13),
                                dropdownColor: AppColors.card,
                                underline: const SizedBox(),
                                items: [
                                  const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('Direct connection')),
                                  for (final h in sshHosts)
                                    DropdownMenuItem<String?>(
                                        value: h.id,
                                        child: Text(
                                            'via ${h.label.isEmpty ? h.host : h.label}')),
                                ],
                                onChanged: (v) => setState(() =>
                                    _jumpHostIds = v == null ? [] : [v]),
                              ),
                            ),
                          ]),
                        ],
                      );
                    }),
                  ],

                  if (!_isRdp) ...[
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
                    if (_authType == AuthType.agent) ...[
                      _divider(),
                      AgentStatusLine(
                          key: const ValueKey('auth-agent-status'),
                          probe: _probeAgent),
                    ],
                  ]),

                  const SizedBox(height: 16),
                  _sectionLabel('CONNECTION CHAIN'),
                  const SizedBox(height: 6),
                  Builder(builder: (context) {
                    final allHosts = context.watch<HostProvider>().allHosts;
                    final existingId = widget.existing?.id;
                    final otherHosts = allHosts
                        .where((h) => h.id != existingId)
                        .toList();
                    if (otherHosts.isEmpty) return const SizedBox.shrink();
                    // Resolve ids → hosts in order, dropping any that no
                    // longer exist (host deleted while referenced).
                    final chainHosts = _jumpHostIds
                        .map((id) =>
                            otherHosts.where((h) => h.id == id).firstOrNull)
                        .whereType<Host>()
                        .toList();
                    if (chainHosts.length != _jumpHostIds.length) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() => _jumpHostIds =
                              chainHosts.map((h) => h.id).toList());
                        }
                      });
                    }
                    return ListenableBuilder(
                      // Live-update the bottom card while typing label/host.
                      listenable: Listenable.merge(
                          [_labelCtrl, _usernameCtrl, _hostCtrl]),
                      builder: (context, _) => HostChainEditor(
                        currentHostLabel: _currentHostLabel(),
                        currentHostOs: widget.existing?.detectedOs,
                        chain: chainHosts,
                        agentForwarding: _agentForwarding,
                        candidates: otherHosts,
                        onChanged: (ids) =>
                            setState(() => _jumpHostIds = ids),
                      ),
                    );
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
                      value: _recordingRedaction,
                      onChanged: (v) =>
                          setState(() => _recordingRedaction = v),
                      title: const Text(
                        'Redact secrets in recordings',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 13),
                      ),
                      subtitle: const Text(
                        'Mask passwords/tokens before writing .cast (requires the global setting)',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 11),
                      ),
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 2),
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
                      title: const Row(children: [
                        Flexible(
                          child: Text(
                            'Agent forwarding',
                            style: TextStyle(
                                color: AppColors.textPrimary, fontSize: 13),
                          ),
                        ),
                        SizedBox(width: 4),
                        Tooltip(
                          message:
                              'SSH Agent auth: your agent\'s keys log you in '
                              'to THIS host.\n'
                              'Agent forwarding: this host can borrow your '
                              'local keys to reach other places (git pull, '
                              'ssh to the next hop). Private keys never '
                              'leave your machine.\n'
                              'Only enable for trusted hosts — root on the '
                              'host can use your keys while you are '
                              'connected.',
                          child: Icon(Icons.info_outline,
                              size: 13, color: AppColors.textTertiary),
                        ),
                      ]),
                      subtitle: const Text(
                        'Let this host use your local SSH keys for onward '
                        'connections — git, ssh to other servers (like '
                        'ssh -A). Applies on next connect.',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 11),
                      ),
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 2),
                      activeThumbColor: AppColors.accent,
                    ),
                    SwitchListTile(
                      value: _osc52Clipboard,
                      onChanged: (v) => setState(() => _osc52Clipboard = v),
                      title: const Text(
                        'OSC 52 clipboard',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 13),
                      ),
                      subtitle: const Text(
                        'Let remote apps (tmux, vim) set your local clipboard. '
                        'Write-only. Off by default — only enable for hosts you '
                        'trust.',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 11),
                      ),
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 2),
                      activeThumbColor: AppColors.accent,
                    ),
                    // Zero-click feedback: probes on appearance. The auth
                    // section owns the line when auth = SSH Agent (spec: one
                    // probe, no duplicate row).
                    if (_agentForwarding && _authType != AuthType.agent)
                      AgentStatusLine(
                          key: const ValueKey('forwarding-status'),
                          probe: _probeAgent),
                  ]),

                  const SizedBox(height: 16),
                  _sectionLabel('SESSION TEMPLATE'),
                  const SizedBox(height: 6),
                  _Card(children: [
                    _PanelField(
                        controller: _workingDirCtrl,
                        hint: 'Working directory (bash/zsh only)',
                        icon: Icons.folder_open),
                    _divider(),
                    for (var i = 0; i < _envRows.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: Row(children: [
                          const Icon(Icons.data_object,
                              size: 16, color: AppColors.textTertiary),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _envRows[i].key,
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 13),
                              decoration: const InputDecoration(
                                hintText: 'NAME',
                                hintStyle: TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 13),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              validator: (v) {
                                final k = v?.trim() ?? '';
                                if (k.isEmpty) return null;
                                if (!ShellIntegrationService.isValidEnvKey(
                                    k)) {
                                  return 'A–Z, 0–9, _ only';
                                }
                                // A map literal would silently keep only the
                                // last duplicate — surface it instead.
                                final dups = _envRows
                                    .where((r) => r.key.text.trim() == k)
                                    .length;
                                return dups > 1 ? 'Duplicate name' : null;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _envRows[i].value,
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 13),
                              decoration: const InputDecoration(
                                hintText: 'value',
                                hintStyle: TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 13),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close,
                                size: 14, color: AppColors.textTertiary),
                            onPressed: () => setState(() {
                              final row = _envRows.removeAt(i);
                              // Dispose after the frame: the row's fields
                              // are still mounted during this build.
                              WidgetsBinding.instance
                                  .addPostFrameCallback((_) {
                                row.key.dispose();
                                row.value.dispose();
                              });
                            }),
                          ),
                        ]),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _envRows.add((
                              key: TextEditingController(),
                              value: TextEditingController(),
                            ))),
                        icon: const Icon(Icons.add,
                            size: 14, color: AppColors.accent),
                        label: const Text('Add env variable',
                            style: TextStyle(
                                color: AppColors.accent, fontSize: 12)),
                      ),
                    ),
                    _divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.play_arrow_outlined,
                                size: 16, color: AppColors.textTertiary),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _startupSnippetCtrl,
                              minLines: 2,
                              maxLines: 4,
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontFamily: 'monospace'),
                              decoration: const InputDecoration(
                                hintText:
                                    'Startup snippet — typed into the shell '
                                    'after connect. Skipped when tmux is on.',
                                hintStyle: TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 12),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _divider(),
                    _TemplateDropdown<String>(
                      icon: Icons.palette_outlined,
                      value: _templateTheme,
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('Theme: follow global')),
                        for (final name in kTerminalThemeNames)
                          DropdownMenuItem<String?>(
                              value: name, child: Text(name)),
                      ],
                      onChanged: (v) => setState(() => _templateTheme = v),
                    ),
                    _divider(),
                    _TemplateDropdown<String>(
                      icon: Icons.text_fields,
                      value: _templateFont,
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('Font: follow global')),
                        for (final f in kBundledTerminalFonts)
                          DropdownMenuItem<String?>(value: f, child: Text(f)),
                      ],
                      onChanged: (v) => setState(() => _templateFont = v),
                      trailing: SizedBox(
                        width: 56,
                        child: TextFormField(
                          controller: _fontSizeCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'size',
                            hintStyle: TextStyle(
                                color: AppColors.textTertiary, fontSize: 13),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          validator: (v) {
                            final t = v?.trim() ?? '';
                            if (t.isEmpty) return null;
                            final d = double.tryParse(t);
                            return (d == null || d < 6 || d > 40)
                                ? '6–40'
                                : null;
                          },
                        ),
                      ),
                    ),
                    _divider(),
                    _TemplateDropdown<String>(
                      icon: Icons.terminal_outlined,
                      value: _templateTermType,
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('TERM: follow global')),
                        for (final t in kTermTypes)
                          DropdownMenuItem<String?>(value: t, child: Text(t)),
                      ],
                      onChanged: (v) =>
                          setState(() => _templateTermType = v),
                    ),
                    _divider(),
                    _TemplateDropdown<bool>(
                      icon: Icons.grid_view_outlined,
                      value: _tmuxOverride,
                      items: const [
                        DropdownMenuItem<bool?>(
                            value: null, child: Text('tmux: follow global')),
                        DropdownMenuItem<bool?>(
                            value: true, child: Text('tmux: always on')),
                        DropdownMenuItem<bool?>(
                            value: false, child: Text('tmux: always off')),
                      ],
                      onChanged: (v) => setState(() => _tmuxOverride = v),
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
                  ], // end !_isRdp (SSH-only sections)
                  if (_isRdp) const SizedBox(height: 24),
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
            child: Row(
              children: [
                Text(
                  _isNew ? 'New Host' : 'Edit Host',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                if (_isRdp) ...[
                  const SizedBox(width: 8),
                  const RdpBadge(),
                ],
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

/// One SESSION TEMPLATE override row: nullable dropdown (null = follow
/// global) with the shared panel styling, plus an optional trailing field.
class _TemplateDropdown<T> extends StatelessWidget {
  final IconData icon;
  final T? value;
  final List<DropdownMenuItem<T?>> items;
  final ValueChanged<T?> onChanged;
  final Widget? trailing;
  const _TemplateDropdown({
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final dropdown = DropdownButton<T?>(
      value: value,
      isExpanded: true,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      dropdownColor: AppColors.card,
      underline: const SizedBox(),
      items: items,
      onChanged: onChanged,
    );
    return _DropdownRow(
      icon: icon,
      child: trailing == null
          ? dropdown
          : Row(children: [
              Expanded(child: dropdown),
              const SizedBox(width: 8),
              trailing!,
            ]),
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
