import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../../models/host.dart';
import '../../models/proxy_settings.dart';
import '../../providers/host_provider.dart';
import '../../providers/key_provider.dart';
import '../../providers/settings_provider.dart' show kTermTypes;
import '../../services/agent_probe.dart';
import '../../services/os_detection.dart';
import '../../services/shell_integration_service.dart';
import '../../services/ssh_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/terminal_themes.dart';
import '../agent_status_line.dart';
import '../host_chain_editor.dart';
import '../network_discovery_sheet.dart';
import '../protocol_badge.dart';
import '../switch_row_tile.dart';
import '../terminal_appearance_controls.dart' show kBundledTerminalFonts;

part 'chain_section.dart';
part 'credentials_section.dart';
part 'fields.dart';
part 'footer.dart';
part 'general_section.dart';
part 'header.dart';
part 'options_section.dart';
part 'protocol_switch.dart';
part 'proxy_section.dart';
part 'rdp_section.dart';
part 'remote_desktop_section.dart';
part 'sftp_section.dart';
part 'template_section.dart';

class HostDetailPanel extends StatefulWidget {
  final Host? existing;
  final String? initialGroup;
  final String? initialHost;
  final int? initialPort;
  final String? initialLabel;
  final HostProtocol? initialProtocol;
  final VoidCallback onClose;
  final Future<void> Function(Host host, String password) onSave;

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
  bool _saving = false;
  bool _testing = false;
  ({bool success, int latencyMs, String? error})? _testResult;
  bool _autoRecord = false;
  bool _recordingRedaction = true;
  bool _shellIntegration = true;
  bool _agentForwarding = false;
  bool _osc52Clipboard = false;
  ProxyType _proxyType = ProxyType.none;
  late final TextEditingController _proxyHostCtrl;
  late final TextEditingController _proxyPortCtrl;
  late final TextEditingController _proxyUsernameCtrl;
  late final TextEditingController _proxyPasswordCtrl;
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
  bool _remoteClipboard = true;

  bool get _isNew => widget.existing == null;
  bool get _isRdp => _protocol == HostProtocol.rdp;

  /// True for any graphical (non-SSH) protocol — these share password-only
  /// auth and hide all SSH-only sections.
  bool get _isGraphical => _protocol != HostProtocol.ssh;

  /// setState for the section widgets in the part files.
  void _set(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    final h = widget.existing;
    _protocol = h?.protocol ?? widget.initialProtocol ?? HostProtocol.ssh;
    _domainCtrl = TextEditingController(text: h?.domain ?? '');
    _rdpSecurity = h?.rdpSecurity ?? RdpSecurityMode.auto;
    _remoteClipboard = h?.remoteClipboard ?? true;
    _hostCtrl = TextEditingController(
      text: h?.host ?? widget.initialHost ?? '',
    );
    _labelCtrl = TextEditingController(
      text: h?.label ?? widget.initialLabel ?? '',
    );
    _groupCtrl = TextEditingController(
      text: h?.group ?? widget.initialGroup ?? '',
    );
    _tagsCtrl = TextEditingController(text: h?.tags.join(', ') ?? '');
    _portCtrl = TextEditingController(
      text: (h?.port ?? widget.initialPort ?? _protocol.defaultPort).toString(),
    );
    _usernameCtrl = TextEditingController(text: h?.username ?? '');
    _passwordCtrl = TextEditingController();
    _authType = h?.authType ?? AuthType.password;
    _selectedKeyId = h?.keyId;
    _autoRecord = h?.autoRecord ?? false;
    _recordingRedaction = h?.recordingRedaction ?? true;
    _shellIntegration = h?.shellIntegration ?? true;
    _agentForwarding = h?.agentForwarding ?? false;
    _osc52Clipboard = h?.osc52Clipboard ?? false;
    _proxyType = h?.proxyType ?? ProxyType.none;
    _proxyHostCtrl = TextEditingController(text: h?.proxyHost ?? '');
    _proxyPortCtrl = TextEditingController(
      text: h?.proxyPort?.toString() ?? '',
    );
    _proxyUsernameCtrl = TextEditingController(text: h?.proxyUsername ?? '');
    _proxyPasswordCtrl = TextEditingController();
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
    if (h != null &&
        (_authType == AuthType.password || _proxyType != ProxyType.none)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _loadExistingPassword(h.id),
      );
    }
  }

  Future<void> _loadExistingPassword(String hostId) async {
    if (!mounted) return;
    final ssh = context.read<SshService>();
    if (_authType == AuthType.password) {
      final pw = await ssh.loadPassword(hostId);
      if (mounted &&
          pw != null &&
          pw.isNotEmpty &&
          _passwordCtrl.text.isEmpty) {
        setState(() => _passwordCtrl.text = pw);
      }
    }
    if (_proxyType != ProxyType.none) {
      final proxyPw = await ssh.loadProxyPassword(hostId);
      if (mounted &&
          proxyPw != null &&
          proxyPw.isNotEmpty &&
          _proxyPasswordCtrl.text.isEmpty) {
        setState(() => _proxyPasswordCtrl.text = proxyPw);
      }
    }
  }

  void _clearTestResult() {
    if (_testResult != null || _testing) {
      setState(() {
        _testResult = null;
        _testing = false;
      });
    }
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
    final keyId = _authType == AuthType.privateKey ? _selectedKeyId : null;
    return probeAgentStatus(
      loadKeychainIdentities: () async => await loader?.call(keyId) ?? const [],
    );
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
      if (next != HostProtocol.ssh) {
        // RDP and VNC support password auth only.
        _authType = AuthType.password;
        _selectedKeyId = null;
      }
      _testResult = null;
    });
  }

  @override
  void dispose() {
    for (final c in [
      _hostCtrl,
      _labelCtrl,
      _groupCtrl,
      _tagsCtrl,
      _portCtrl,
      _usernameCtrl,
      _passwordCtrl,
      _sftpCommand,
      _workingDirCtrl,
      _startupSnippetCtrl,
      _fontSizeCtrl,
      _domainCtrl,
      _proxyHostCtrl,
      _proxyPortCtrl,
      _proxyUsernameCtrl,
      _proxyPasswordCtrl,
    ]) {
      c.dispose();
    }
    for (final r in _envRows) {
      r.key.dispose();
      r.value.dispose();
    }
    super.dispose();
  }

  /// Empty means the protocol default. Anything else is range-checked by
  /// [_validatePort] before Save / Test reach this.
  int get _port {
    final t = _portCtrl.text.trim();
    return t.isEmpty ? _protocol.defaultPort : int.parse(t);
  }

  static String? _validatePort(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    final n = int.tryParse(t);
    return n == null || n < 1 || n > 65535 ? 'Invalid (1–65535)' : null;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    setState(() => _saving = true);
    final tags = _tagsCtrl.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final host = Host(
      id: widget.existing?.id,
      createdAt: widget.existing?.createdAt,
      label: _labelCtrl.text.trim().isEmpty
          ? _hostCtrl.text.trim()
          : _labelCtrl.text.trim(),
      host: _hostCtrl.text.trim(),
      port: _port,
      username: _usernameCtrl.text.trim(),
      protocol: _protocol,
      domain: _isRdp && _domainCtrl.text.trim().isNotEmpty
          ? _domainCtrl.text.trim()
          : null,
      rdpSecurity: _rdpSecurity,
      remoteClipboard: _remoteClipboard,
      authType: _isGraphical ? AuthType.password : _authType,
      keyId: !_isGraphical && _authType == AuthType.privateKey
          ? _selectedKeyId
          : null,
      group: _groupCtrl.text.trim(),
      tags: tags,
      autoRecord: !_isGraphical && _autoRecord,
      recordingRedaction: _recordingRedaction,
      shellIntegration: _shellIntegration,
      agentForwarding: !_isGraphical && _agentForwarding,
      osc52Clipboard: !_isGraphical && _osc52Clipboard,
      proxyType: _isGraphical ? ProxyType.none : _proxyType,
      proxyHost: _isGraphical || _proxyType == ProxyType.none
          ? null
          : _proxyHostCtrl.text.trim(),
      proxyPort: _isGraphical || _proxyType == ProxyType.none
          ? null
          : int.tryParse(_proxyPortCtrl.text.trim()),
      proxyUsername:
          _isGraphical ||
              _proxyType == ProxyType.none ||
              _proxyUsernameCtrl.text.trim().isEmpty
          ? null
          : _proxyUsernameCtrl.text.trim(),
      jumpHostIds: _jumpHostIds,
      sftpMode: _isGraphical ? SftpMode.normal : _sftpMode,
      sftpServerCommand: !_isGraphical && _sftpMode == SftpMode.custom
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
    final ssh = context.read<SshService>();
    try {
      if (!_isGraphical && _proxyType != ProxyType.none) {
        await ssh.saveProxyPassword(host.id, _proxyPasswordCtrl.text);
      }
      await widget.onSave(host, _passwordCtrl.text);
      if (mounted) widget.onClose();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Validates every section (they are all built — see [build]) and, when
  /// something is wrong, scrolls the topmost invalid field into view: Save and
  /// Enter can sit far from it (pinned footer, Enter in the label).
  bool _validate() {
    final invalid = _formKey.currentState?.validateGranularly() ?? const {};
    if (invalid.isEmpty) return true;
    double top(FormFieldState<Object?> f) {
      final box = f.context.findRenderObject();
      return box is RenderBox && box.attached
          ? box.localToGlobal(Offset.zero).dy
          : double.infinity;
    }

    final first = invalid.reduce((a, b) => top(b) < top(a) ? b : a);
    Scrollable.ensureVisible(
      first.context,
      alignment: 0.2,
      duration: const Duration(milliseconds: 200),
    );
    return false;
  }

  /// Enter in a single-line field: same as Save (validates first).
  void _submit() {
    if (!_saving) _save();
  }

  /// Footer Delete (existing hosts only): confirm, delete, close.
  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null || _saving) return;
    final name = existing.label.isEmpty ? existing.host : existing.label;
    final ok = await showYsConfirm(
      context,
      title: 'Delete host?',
      message: '"$name" and its saved password will be removed.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await context.read<HostProvider>().deleteHost(existing.id);
    if (mounted) widget.onClose();
  }

  Future<void> _test() async {
    if (!_validate()) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });

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
      port: _port,
      username: _usernameCtrl.text.trim(),
      authType: _authType,
      keyId: _authType == AuthType.privateKey ? _selectedKeyId : null,
      group: '',
      tags: const [],
      jumpHostIds: _jumpHostIds,
      sftpMode: _sftpMode,
      sftpServerCommand: _sftpMode == SftpMode.custom
          ? _sftpCommand.text.trim()
          : null,
    );

    final result = await context.read<SshService>().testConnection(
      host,
      password: _passwordCtrl.text,
      keyEntry: keyEntry,
      jumpChain: jumpChain,
    );

    if (mounted) {
      setState(() {
        _testing = false;
        _testResult = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: YsColors.sidebar,
        border: Border(left: BorderSide(color: YsColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(form: this),
          Expanded(
            child: Form(
              key: _formKey,
              // Not a lazy ListView: every section stays built, so every
              // FormField is registered and Save / Enter validate the whole
              // form, not just the part on screen.
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  YsSpace.s4,
                  YsSpace.s4,
                  YsSpace.s4,
                  YsSpace.s5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ProtocolSwitch(form: this),
                    _GeneralSection(form: this),
                    _CredentialsSection(form: this),
                    if (_isRdp) _RdpSection(form: this),
                    if (!_isGraphical) _AuthMethodSection(form: this),
                    _GroupTagsSection(form: this),
                    if (_isGraphical) _RemoteDesktopSection(form: this),
                    if (!_isGraphical) ...[
                      _ChainSection(form: this),
                      _ProxySection(form: this),
                      _SftpSection(form: this),
                      _OptionsSection(form: this),
                      _TemplateSection(form: this),
                    ],
                  ],
                ),
              ),
            ),
          ),
          _PanelFooter(form: this),
        ],
      ),
    );
  }
}
