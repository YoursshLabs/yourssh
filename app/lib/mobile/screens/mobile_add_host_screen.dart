import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../../models/host.dart';
import '../../models/ssh_key.dart';
import '../../providers/host_provider.dart';
import '../../providers/key_provider.dart';
import '../../providers/session_provider.dart';
import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';
import '../widgets/button_label.dart';
import '../widgets/list_group.dart';
import '../widgets/section_header.dart';
import '../widgets/settings_row.dart';

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

  /// Empty means the default port (22); otherwise it must be 1-65535.
  String? get _portError {
    final t = _port.text.trim();
    if (t.isEmpty) return null;
    final n = int.tryParse(t);
    return n == null || n < 1 || n > 65535 ? 'Invalid (1–65535)' : null;
  }

  bool get _canSave =>
      _portError == null &&
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
    _port.addListener(_onFieldChanged);

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

  /// Persists the form and returns the saved host's id.
  Future<String> _doSave() async {
    final label = _label.text.trim();
    final address = _address.text.trim();
    final username = _username.text.trim();
    // Empty -> default 22; the 1-65535 range is enforced by _canSave.
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
      return existing.id;
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
      return host.id;
    }
  }

  Future<void> _save() async {
    if (!_canSave) return;
    await _doSave();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _saveAndConnect() async {
    if (!_canSave) return;
    final savedId = await _doSave();
    if (!mounted) return;
    // Use the id returned by _doSave — deterministic, no .last assumption.
    final host = context.read<HostProvider>().byId(savedId);
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
      body: SafeArea(
        // FHeader adds the top safe area itself.
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Expanded(
              // Not a lazy list: every field stays mounted so focus traversal
              // (Next) reaches fields that are scrolled out of view.
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  MobileTokens.space4,
                  MobileTokens.space2,
                  MobileTokens.space4,
                  MobileTokens.space5 * 2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return FHeader.nested(
      title: Text(_isEdit ? 'Edit host' : 'New host'),
      prefixes: [
        FButton(
          variant: FButtonVariant.ghost,
          onPress: () => Navigator.of(context).maybePop(),
          child: const Text('Hosts'),
        ),
      ],
      suffixes: [
        FButton(
          variant: FButtonVariant.ghost,
          onPress: _canSave ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }

  // ── Groups ────────────────────────────────────────────────────────────────

  /// A labelled block of stacked fields (section label + fields).
  Widget _section(String label, List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(label),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: MobileTokens.space3),
            children[i],
          ],
        ],
      );

  Widget _generalGroup() => _section('General', [
        _field(
          fieldKey: 'host-label',
          controller: _label,
          label: 'Nickname',
          textInputAction: TextInputAction.next,
        ),
        _field(
          fieldKey: 'host-address',
          controller: _address,
          label: 'Hostname',
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
        ),
        _field(
          fieldKey: 'host-port',
          controller: _port,
          label: 'Port',
          keyboardType: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly],
          textInputAction: TextInputAction.next,
          error: _portError,
        ),
      ]);

  Widget _authGroup(List<SshKeyEntry> keys) {
    final usernameRow = _field(
      fieldKey: 'host-username',
      controller: _username,
      label: 'Username',
      textInputAction: TextInputAction.next,
    );

    if (_isCertOrAgent) {
      return _section('Authentication', [
        usernameRow,
        ListGroup(children: [_CertAgentNoteRow(authType: widget.existing!.authType)]),
      ]);
    }

    return _section('Authentication', [
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
        _field(
          fieldKey: 'host-password',
          controller: _password,
          label: 'Password',
          obscure: true,
          hint: _isEdit ? 'Leave blank to keep current' : null,
          textInputAction: TextInputAction.done,
        ),
    ]);
  }

  Widget _advancedGroup() => _section('Advanced', [
        _field(
          fieldKey: 'host-group',
          controller: _group,
          label: 'Group',
          hint: 'e.g. Production',
          textInputAction: TextInputAction.next,
        ),
        _field(
          fieldKey: 'host-startup-snippet',
          controller: _snippet,
          label: 'Run on connect',
          hint: 'e.g. tmux attach',
          textInputAction: TextInputAction.done,
        ),
      ]);

  Widget _saveConnectButton() => FButton(
        variant: FButtonVariant.primary,
        size: FButtonSizeVariant.lg,
        onPress: _canSave ? _saveAndConnect : null,
        child: const ButtonLabel('Save & connect'),
      );

  // ── Field helper ──────────────────────────────────────────────────────────

  /// A labelled [FTextField]; secrets use [FTextField.password] (obscured,
  /// without the reveal toggle, which the mobile form never had).
  Widget _field({
    required String fieldKey,
    required TextEditingController controller,
    required String label,
    bool obscure = false,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    TextInputAction? textInputAction,
    String? error,
  }) {
    final control = FTextFieldControl.managed(controller: controller);
    if (obscure) {
      return FTextField.password(
        key: Key(fieldKey),
        control: control,
        label: Text(label),
        hint: hint,
        textInputAction: textInputAction ?? TextInputAction.next,
        suffixBuilder: null,
      );
    }
    return FTextField(
      key: Key(fieldKey),
      control: control,
      label: Text(label),
      hint: hint,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      textInputAction: textInputAction,
      error: error == null ? null : Text(error),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Method', style: mobileBody(color: MobileColors.textMuted)),
        const SizedBox(height: MobileTokens.space2),
        Row(
          children: [
            Expanded(
              child: _MethodPill(
                label: 'Password',
                selected: !useKey,
                onTap: () => onChanged(false),
              ),
            ),
            const SizedBox(width: MobileTokens.space2),
            Expanded(
              child: _MethodPill(
                label: 'SSH key',
                selected: useKey,
                onTap: keysAvailable ? () => onChanged(true) : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One option of the method toggle; a disabled one (no keys) has no [onTap].
class _MethodPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _MethodPill({
    required this.label,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: FButton(
        variant: selected ? FButtonVariant.primary : FButtonVariant.outline,
        onPress: onTap,
        child: ButtonLabel(label),
      ),
    );
  }
}

/// Select for picking an SSH key (shown when auth method = SSH key).
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
    final known = keys.any((k) => k.id == selectedId);
    // Items are keyed by display text, so equal labels are disambiguated with
    // the tail of the id; every key stays selectable.
    final counts = <String, int>{};
    for (final k in keys) {
      counts[k.label] = (counts[k.label] ?? 0) + 1;
    }
    String shown(SshKeyEntry k) => counts[k.label]! > 1
        ? '${k.label} (…${k.id.length > 6 ? k.id.substring(k.id.length - 6) : k.id})'
        : k.label;
    return FSelect<String>(
      items: {for (final k in keys) shown(k): k.id},
      control: FSelectControl.managed(
        initial: known ? selectedId : null,
        onChange: onChanged,
      ),
      label: const Text('Key'),
      hint: 'Select a key',
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
          const Icon(FLucideIcons.shieldCheck,
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
