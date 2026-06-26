import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/host.dart';
import '../../models/ssh_key.dart';
import '../../providers/host_provider.dart';
import '../../providers/key_provider.dart';
import '../../providers/session_provider.dart';
import '../security/app_lock_gate.dart';
import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';
import '../widgets/list_group.dart';

/// Grouped add/edit host form for mobile (Design 02).
///
/// Pass [existing] to edit; omit to create. The screen preserves id, tags,
/// jump chain, RDP/VNC, cert/agent fields on edit — only what's shown is
/// modified. Group maps to/from the first host tag; "Run on connect" maps to
/// [Host.startupSnippet].
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
  final _group = TextEditingController();
  final _snippet = TextEditingController();

  bool _useKey = false;
  String? _keyId;

  bool get _isEdit => widget.existing != null;

  /// Certificate and agent auth have no UI in this form; we show a read-only
  /// note and preserve auth untouched on save.
  bool get _isCertOrAgent {
    final a = widget.existing?.authType;
    return a == AuthType.certificate || a == AuthType.agent;
  }

  bool get _canSave =>
      _label.text.trim().isNotEmpty &&
      _address.text.trim().isNotEmpty &&
      _username.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Rebuild when any required field changes so Save button enables/disables.
    _label.addListener(_onFieldChanged);
    _address.addListener(_onFieldChanged);
    _username.addListener(_onFieldChanged);

    final h = widget.existing;
    if (h != null) {
      _label.text = h.label;
      _address.text = h.host;
      _port.text = '${h.port}';
      _username.text = h.username;
      _useKey = h.authType == AuthType.privateKey;
      _keyId = h.keyId;
      // Group = first tag (round-trip: save writes it back as the first tag).
      _group.text = h.tags.isNotEmpty ? h.tags.first : '';
      _snippet.text = h.startupSnippet ?? '';
    }
  }

  void _onFieldChanged() => setState(() {});

  @override
  void dispose() {
    for (final c in [
      _label,
      _address,
      _port,
      _username,
      _password,
      _group,
      _snippet,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Save helpers ──────────────────────────────────────────────────────────

  /// Builds the updated tag list: replaces the first tag slot with [_group]
  /// (or removes it if blank), while preserving additional existing tags.
  List<String> _buildTags(List<String> existingTags) {
    final groupVal = _group.text.trim();
    final rest = existingTags.length > 1 ? existingTags.sublist(1) : <String>[];
    if (groupVal.isEmpty) return rest;
    return [groupVal, ...rest];
  }

  Future<void> _doSave() async {
    final label = _label.text.trim();
    final address = _address.text.trim();
    final username = _username.text.trim();
    final port = int.tryParse(_port.text.trim()) ?? 22;
    final snippetVal = _snippet.text.trim();
    final provider = context.read<HostProvider>();
    final existing = widget.existing;

    if (existing != null) {
      final newTags = _buildTags(existing.tags);
      if (_isCertOrAgent) {
        // Preserve authType + keyId — never silently downgrade cert/agent auth.
        final updated = existing.copyWith(
          label: label,
          host: address,
          port: port,
          username: username,
          startupSnippet: snippetVal.isEmpty ? null : snippetVal,
        );
        // copyWith has no tags parameter — mutate directly after copy.
        updated.tags
          ..clear()
          ..addAll(newTags);
        await provider.updateHost(updated);
      } else {
        final authType = _useKey ? AuthType.privateKey : AuthType.password;
        final keyId = _useKey ? _keyId : null;
        final updated = existing.copyWith(
          label: label,
          host: address,
          port: port,
          username: username,
          authType: authType,
          keyId: keyId,
          startupSnippet: snippetVal.isEmpty ? null : snippetVal,
        );
        updated.tags
          ..clear()
          ..addAll(newTags);
        await provider.updateHost(
          updated,
          password: _useKey ? null : _password.text,
        );
      }
    } else {
      final authType = _useKey ? AuthType.privateKey : AuthType.password;
      final keyId = _useKey ? _keyId : null;
      final groupVal = _group.text.trim();
      final host = Host(
        label: label,
        host: address,
        port: port,
        username: username,
        authType: authType,
        keyId: keyId,
        tags: groupVal.isEmpty ? [] : [groupVal],
        startupSnippet: snippetVal.isEmpty ? null : snippetVal,
      );
      await provider.addHost(host, password: _useKey ? null : _password.text);
    }
  }

  Future<void> _save() async {
    if (!_canSave) return;
    await _doSave();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _saveAndConnect() async {
    if (!_canSave) return;
    await _doSave();
    if (!mounted) return;
    // Look up the just-saved host by id so we get the freshest copy.
    final hostId = widget.existing?.id ?? context.read<HostProvider>().allHosts.last.id;
    final host = context.read<HostProvider>().byId(hostId);
    if (host != null && mounted) {
      context.read<SessionProvider>().connectAny(host);
    }
    if (mounted) Navigator.of(context).pop();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final keys = context.watch<KeyProvider>().keys;

    return Scaffold(
      backgroundColor: MobileColors.bg,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            MobileTokens.space4,
            MobileTokens.space4,
            MobileTokens.space4,
            MobileTokens.space5 * 2,
          ),
          children: [
            _generalGroup(),
            const SizedBox(height: MobileTokens.space4),
            _authGroup(keys),
            const SizedBox(height: MobileTokens.space4),
            _advancedGroup(),
            const SizedBox(height: MobileTokens.space5),
            _saveConnectButton(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: MobileColors.bg,
      elevation: 0,
      automaticallyImplyLeading: false,
      leading: TextButton(
        onPressed: () => Navigator.of(context).maybePop(),
        style: TextButton.styleFrom(padding: EdgeInsets.zero),
        child: Text(
          'Hosts',
          style: mobileBody(color: MobileColors.accent, weight: FontWeight.w500),
        ),
      ),
      leadingWidth: 72,
      centerTitle: true,
      title: Text(
        _isEdit ? 'Edit host' : 'New host',
        style: mobileHeading(size: 17),
      ),
      actions: [
        TextButton(
          onPressed: _canSave ? _save : null,
          child: Text(
            'Save',
            style: mobileBody(
              color: _canSave ? MobileColors.accent : MobileColors.textFaint,
              weight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: MobileTokens.space2),
      ],
    );
  }

  // ── Groups ────────────────────────────────────────────────────────────────

  Widget _generalGroup() => ListGroup(
        label: 'General',
        children: [
          _inlineField(
            fieldKey: 'host-label',
            controller: _label,
            label: 'Nickname',
            textInputAction: TextInputAction.next,
          ),
          _inlineField(
            fieldKey: 'host-address',
            controller: _address,
            label: 'Hostname',
            mono: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
          ),
          _inlineField(
            fieldKey: 'host-port',
            controller: _port,
            label: 'Port',
            mono: true,
            keyboardType: TextInputType.number,
            formatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.next,
          ),
        ],
      );

  Widget _authGroup(List<SshKeyEntry> keys) {
    final usernameRow = _inlineField(
      fieldKey: 'host-username',
      controller: _username,
      label: 'Username',
      mono: true,
      textInputAction: TextInputAction.next,
    );

    if (_isCertOrAgent) {
      return ListGroup(
        label: 'Authentication',
        children: [
          usernameRow,
          _CertAgentNoteRow(authType: widget.existing!.authType),
        ],
      );
    }

    return ListGroup(
      label: 'Authentication',
      children: [
        usernameRow,
        _MethodRow(
          useKey: _useKey,
          keysAvailable: keys.isNotEmpty,
          onChanged: (v) => setState(() => _useKey = v),
        ),
        if (_useKey)
          _KeyPickerRow(
            keys: keys,
            selectedId: _keyId,
            onChanged: (v) => setState(() => _keyId = v),
          )
        else
          _inlineField(
            fieldKey: 'host-password',
            controller: _password,
            label: 'Password',
            obscure: true,
            hint: _isEdit ? 'Leave blank to keep current' : null,
            textInputAction: TextInputAction.done,
          ),
        const _BiometricRow(),
      ],
    );
  }

  Widget _advancedGroup() => ListGroup(
        label: 'Advanced',
        children: [
          _inlineField(
            fieldKey: 'host-group',
            controller: _group,
            label: 'Group',
            hint: 'e.g. Production',
            textInputAction: TextInputAction.next,
          ),
          _inlineField(
            fieldKey: 'host-startup-snippet',
            controller: _snippet,
            label: 'Run on connect',
            mono: true,
            hint: 'e.g. tmux attach',
            textInputAction: TextInputAction.done,
          ),
        ],
      );

  Widget _saveConnectButton() => SizedBox(
        width: double.infinity,
        height: MobileTokens.touchTarget + 4,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: MobileColors.accent,
            foregroundColor: Colors.black,
            disabledBackgroundColor: MobileColors.accentSoft,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: _canSave ? _saveAndConnect : null,
          child: Text(
            'Save & connect',
            style: mobileBody(
              color: _canSave ? Colors.black : MobileColors.textFaint,
              weight: FontWeight.w600,
              size: 16,
            ),
          ),
        ),
      );

  // ── Field helpers ─────────────────────────────────────────────────────────

  Widget _inlineField({
    required String fieldKey,
    required TextEditingController controller,
    required String label,
    bool obscure = false,
    bool mono = false,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    TextInputAction? textInputAction,
  }) {
    final valueStyle = mono
        ? mobileMono(size: 14, color: MobileColors.textPrimary)
        : mobileBody(size: 15, color: MobileColors.textPrimary);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MobileTokens.space4,
        vertical: MobileTokens.space3,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child:
                Text(label, style: mobileBody(color: MobileColors.textMuted)),
          ),
          Expanded(
            child: TextField(
              key: Key(fieldKey),
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              inputFormatters: formatters,
              textInputAction: textInputAction,
              style: valueStyle,
              textAlign: TextAlign.end,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle:
                    mobileMono(size: 13, color: MobileColors.textFaint),
                isDense: true,
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              cursorColor: MobileColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Auth sub-widgets ─────────────────────────────────────────────────────────

/// Row that toggles between Password and SSH Key auth method.
class _MethodRow extends StatelessWidget {
  final bool useKey;
  final bool keysAvailable;
  final ValueChanged<bool> onChanged;

  const _MethodRow({
    required this.useKey,
    required this.keysAvailable,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MobileTokens.space4,
        vertical: MobileTokens.space3,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child:
                Text('Method', style: mobileBody(color: MobileColors.textMuted)),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _MethodPill(
                  label: 'Password',
                  selected: !useKey,
                  onTap: () => onChanged(false),
                ),
                const SizedBox(width: MobileTokens.space2),
                _MethodPill(
                  label: 'SSH key',
                  selected: useKey,
                  enabled: keysAvailable,
                  onTap: keysAvailable ? () => onChanged(true) : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodPill extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const _MethodPill({
    required this.label,
    required this.selected,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? MobileColors.accent : MobileColors.surfaceAlt;
    final fg = selected
        ? Colors.black
        : (enabled ? MobileColors.textPrimary : MobileColors.textFaint);

    final pill = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MobileTokens.space3,
        vertical: MobileTokens.space1 + 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(MobileTokens.radiusPill),
        border: Border.all(
          color: selected ? MobileColors.accent : MobileColors.border,
        ),
      ),
      child: Text(
        label,
        style: mobileBody(size: 13, color: fg, weight: FontWeight.w500),
      ),
    );

    if (onTap == null) return pill;
    return InkWell(
      borderRadius: BorderRadius.circular(MobileTokens.radiusPill),
      onTap: onTap,
      child: pill,
    );
  }
}

/// Dropdown row for picking an SSH key (shown when auth method = SSH key).
class _KeyPickerRow extends StatelessWidget {
  final List<SshKeyEntry> keys;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  const _KeyPickerRow({
    required this.keys,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MobileTokens.space4,
        vertical: MobileTokens.space3,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text('Key', style: mobileBody(color: MobileColors.textMuted)),
          ),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selectedId,
                isExpanded: true,
                alignment: Alignment.centerRight,
                style: mobileMono(size: 13, color: MobileColors.textMuted),
                dropdownColor: MobileColors.surface,
                iconEnabledColor: MobileColors.textFaint,
                items: [
                  for (final k in keys)
                    DropdownMenuItem(
                      value: k.id,
                      child: Text(
                        k.label,
                        textAlign: TextAlign.end,
                        style: mobileMono(
                            size: 13, color: MobileColors.textPrimary),
                      ),
                    ),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only auth note shown when editing a cert- or agent-authenticated host.
/// The auth type is preserved as-is on save.
class _CertAgentNoteRow extends StatelessWidget {
  final AuthType authType;
  const _CertAgentNoteRow({required this.authType});

  @override
  Widget build(BuildContext context) {
    final kind =
        authType == AuthType.certificate ? 'Certificate' : 'SSH agent';
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MobileTokens.space4,
        vertical: MobileTokens.space3,
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user_outlined,
              color: MobileColors.textFaint, size: 16),
          const SizedBox(width: MobileTokens.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$kind authentication',
                    style: mobileBody(color: MobileColors.textPrimary)),
                const SizedBox(height: 2),
                Text('Configured on desktop — kept unchanged',
                    style: mobileBody(
                        size: 12, color: MobileColors.textFaint)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Amber toggle row for Face ID / biometric app-lock (reads/writes
/// [kAppLockPrefKey] in SharedPreferences — same key as AppLockGate).
class _BiometricRow extends StatefulWidget {
  const _BiometricRow();

  @override
  State<_BiometricRow> createState() => _BiometricRowState();
}

class _BiometricRowState extends State<_BiometricRow> {
  bool _enabled = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _enabled = p.getBool(kAppLockPrefKey) ?? true;
        _loaded = true;
      });
    });
  }

  Future<void> _toggle(bool v) async {
    setState(() => _enabled = v);
    final p = await SharedPreferences.getInstance();
    await p.setBool(kAppLockPrefKey, v);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MobileTokens.space4,
        vertical: MobileTokens.space1,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('Unlock with biometrics',
                style: mobileBody(color: MobileColors.textPrimary)),
          ),
          Switch(
            value: _enabled,
            onChanged: _toggle,
            activeThumbColor: MobileColors.accent,
            activeTrackColor: MobileColors.accent.withAlpha(77),
          ),
        ],
      ),
    );
  }
}
