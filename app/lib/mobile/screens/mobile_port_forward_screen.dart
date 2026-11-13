import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../../models/host.dart';
import '../../models/port_forward.dart';
import '../../providers/port_forward_provider.dart';
import '../../services/port_forward_service.dart';
import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';
import '../widgets/button_label.dart';
import '../widgets/forward_rule_row.dart';
import '../widgets/section_header.dart';

/// Port-forwarding screen scoped to [host]. Reached from Terminal ⋮ menu.
class MobilePortForwardScreen extends StatelessWidget {
  final Host host;

  const MobilePortForwardScreen({super.key, required this.host});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PortForwardProvider>();
    final service = context.read<PortForwardService>();
    final rules =
        provider.forwards.where((f) => f.hostId == host.id).toList();

    return Scaffold(
      backgroundColor: MobileColors.bg,
      body: SafeArea(
        // FHeader adds the top safe area itself.
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FHeader.nested(
              prefixes: [
                Tooltip(
                  message: 'Back',
                  child: FHeaderAction.back(
                    semanticsLabel: 'Back',
                    onPress: () => Navigator.maybePop(context),
                  ),
                ),
              ],
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: MobileColors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      host.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(
                MobileTokens.space4,
                MobileTokens.space3,
                MobileTokens.space4,
                0,
              ),
              child: SectionHeader('Forwarding'),
            ),
            Expanded(
              child: rules.isEmpty
                  ? Center(
                      child: Text(
                        'No forwarding rules for this host',
                        style: mobileBody(
                            size: 14, color: MobileColors.textMuted),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(
                          bottom: MobileTokens.space4 * 4),
                      itemCount: rules.length,
                      itemBuilder: (_, i) {
                        final rule = rules[i];
                        final running = service.isRunning(rule.id) ||
                            rule.status == ForwardStatus.active;
                        return ForwardRuleRow(
                          rule: rule,
                          isRunning: running,
                          onToggle: () {
                            if (running) {
                              service.stop(rule.id);
                            } else {
                              service.start(rule);
                            }
                          },
                        );
                      },
                    ),
            ),
            // Add forwarding rule button
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MobileTokens.space4,
                0,
                MobileTokens.space4,
                MobileTokens.space4,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FButton(
                  variant: FButtonVariant.primary,
                  prefix: const Icon(FLucideIcons.plus),
                  onPress: () => _showAddRuleSheet(context),
                  child: const ButtonLabel('Add forwarding rule'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddRuleSheet(BuildContext context) async {
    final provider = context.read<PortForwardProvider>();
    await showFSheet<void>(
      context: context,
      side: FLayout.btt,
      useSafeArea: true,
      mainAxisMaxRatio: null,
      builder: (ctx) => _AddRuleSheet(hostId: host.id, provider: provider),
    );
  }
}

// ---------------------------------------------------------------------------
// Add-rule bottom sheet
// ---------------------------------------------------------------------------

class _AddRuleSheet extends StatefulWidget {
  final String hostId;
  final PortForwardProvider provider;

  const _AddRuleSheet({required this.hostId, required this.provider});

  @override
  State<_AddRuleSheet> createState() => _AddRuleSheetState();
}

/// Which field a validation message belongs to.
enum _RuleField { localPort, remoteHost, remotePort }

class _AddRuleSheetState extends State<_AddRuleSheet> {
  ForwardType _type = ForwardType.local;
  final _labelCtrl = TextEditingController();
  final _localPortCtrl = TextEditingController();
  final _remoteHostCtrl = TextEditingController();
  final _remotePortCtrl = TextEditingController();

  String? _validationError;
  _RuleField? _errorField;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _localPortCtrl.dispose();
    _remoteHostCtrl.dispose();
    _remotePortCtrl.dispose();
    super.dispose();
  }

  /// Returns the first invalid field with its message, otherwise null.
  ({_RuleField field, String message})? _validate() {
    final localPort = int.tryParse(_localPortCtrl.text.trim());
    if (localPort == null || localPort < 1 || localPort > 65535) {
      return (
        field: _RuleField.localPort,
        message: 'Local port must be between 1 and 65535.',
      );
    }
    if (_type != ForwardType.dynamic) {
      if (_remoteHostCtrl.text.trim().isEmpty) {
        return (
          field: _RuleField.remoteHost,
          message: 'Remote host must not be empty.',
        );
      }
      final remotePort = int.tryParse(_remotePortCtrl.text.trim());
      if (remotePort == null || remotePort < 1 || remotePort > 65535) {
        return (
          field: _RuleField.remotePort,
          message: 'Remote port must be between 1 and 65535.',
        );
      }
    }
    return null;
  }

  void _save() {
    final error = _validate();
    if (error != null) {
      setState(() {
        _validationError = error.message;
        _errorField = error.field;
      });
      return;
    }

    final localPort = int.parse(_localPortCtrl.text.trim());
    final remotePort = _type != ForwardType.dynamic
        ? int.parse(_remotePortCtrl.text.trim())
        : 0;
    final label = _labelCtrl.text.trim().isEmpty
        ? _type.name
        : _labelCtrl.text.trim();

    final rule = PortForward(
      label: label,
      type: _type,
      localPort: localPort,
      remoteHost: _remoteHostCtrl.text.trim(),
      remotePort: remotePort,
      hostId: widget.hostId,
    );
    widget.provider.add(rule);
    Navigator.pop(context);
  }

  void _pickType(ForwardType t) => setState(() {
        _type = t;
        _validationError = null;
        _errorField = null;
      });

  @override
  Widget build(BuildContext context) {
    // The sheet itself lifts above the keyboard; scroll when it gets short.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        MobileTokens.space4,
        MobileTokens.space3,
        MobileTokens.space4,
        MobileTokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add forwarding rule', style: mobileHeading(size: 17)),
          const SizedBox(height: MobileTokens.space3),
          // Type selector
          Row(
            children: [
              for (final (i, t) in ForwardType.values.indexed) ...[
                if (i > 0) const SizedBox(width: MobileTokens.space2),
                Expanded(
                  child: Semantics(
                    selected: _type == t,
                    inMutuallyExclusiveGroup: true,
                    child: FButton(
                      variant: _type == t
                          ? FButtonVariant.primary
                          : FButtonVariant.outline,
                      onPress: () => _pickType(t),
                      child: ButtonLabel(switch (t) {
                        ForwardType.local => 'Local',
                        ForwardType.remote => 'Remote',
                        ForwardType.dynamic => 'Dynamic',
                      }),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: MobileTokens.space3),
          _field('Label (optional)', _labelCtrl),
          const SizedBox(height: MobileTokens.space2),
          _field('Local port', _localPortCtrl,
              numeric: true,
              hint: _type == ForwardType.dynamic ? '1080' : '5432',
              field: _RuleField.localPort),
          if (_type != ForwardType.dynamic) ...[
            const SizedBox(height: MobileTokens.space2),
            _field('Remote host', _remoteHostCtrl,
                hint: 'db-server', field: _RuleField.remoteHost),
            const SizedBox(height: MobileTokens.space2),
            _field('Remote port', _remotePortCtrl,
                numeric: true, hint: '5432', field: _RuleField.remotePort),
          ],
          const SizedBox(height: MobileTokens.space4),
          FButton(
            variant: FButtonVariant.primary,
            onPress: _save,
            child: const ButtonLabel('Add rule'),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    bool numeric = false,
    String? hint,
    _RuleField? field,
  }) {
    return FTextField(
      control: FTextFieldControl.managed(controller: ctrl),
      label: Text(label),
      hint: hint,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      inputFormatters:
          numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
      error: field != null && field == _errorField && _validationError != null
          ? Text(_validationError!)
          : null,
    );
  }
}
