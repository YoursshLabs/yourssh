import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/host.dart';
import '../../models/port_forward.dart';
import '../../providers/port_forward_provider.dart';
import '../../services/port_forward_service.dart';
import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';
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
      appBar: AppBar(
        backgroundColor: MobileColors.surfaceAlt,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: MobileColors.accent, size: 20),
          onPressed: () => Navigator.maybePop(context),
        ),
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
            Text(
              host.label,
              style: mobileBody(size: 16, weight: FontWeight.w600),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton<Never>(
            icon: const Icon(Icons.more_vert,
                color: MobileColors.textMuted, size: 20),
            itemBuilder: (_) => const [],
          ),
        ],
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: MobileColors.accent,
                  foregroundColor: MobileColors.bg,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(MobileTokens.radiusCard),
                  ),
                  padding: const EdgeInsets.symmetric(
                      vertical: MobileTokens.space3),
                ),
                icon: const Icon(Icons.add, size: 20),
                label: Text(
                  'Add forwarding rule',
                  style: mobileBody(
                      size: 15,
                      weight: FontWeight.w600,
                      color: MobileColors.bg),
                ),
                onPressed: () => _showAddRuleSheet(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddRuleSheet(BuildContext context) async {
    final provider = context.read<PortForwardProvider>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MobileColors.surfaceAlt,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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

class _AddRuleSheetState extends State<_AddRuleSheet> {
  ForwardType _type = ForwardType.local;
  final _labelCtrl = TextEditingController();
  final _localPortCtrl = TextEditingController();
  final _remoteHostCtrl = TextEditingController();
  final _remotePortCtrl = TextEditingController();

  String? _validationError;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _localPortCtrl.dispose();
    _remoteHostCtrl.dispose();
    _remotePortCtrl.dispose();
    super.dispose();
  }

  /// Returns an error message if the inputs are invalid, otherwise null.
  String? _validate() {
    final localPort = int.tryParse(_localPortCtrl.text.trim());
    if (localPort == null || localPort < 1 || localPort > 65535) {
      return 'Local port must be between 1 and 65535.';
    }
    if (_type != ForwardType.dynamic) {
      if (_remoteHostCtrl.text.trim().isEmpty) {
        return 'Remote host must not be empty.';
      }
      final remotePort = int.tryParse(_remotePortCtrl.text.trim());
      if (remotePort == null || remotePort < 1 || remotePort > 65535) {
        return 'Remote port must be between 1 and 65535.';
      }
    }
    return null;
  }

  void _save() {
    final error = _validate();
    if (error != null) {
      setState(() => _validationError = error);
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

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        MobileTokens.space4,
        MobileTokens.space3,
        MobileTokens.space4,
        MobileTokens.space4 + viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: MobileColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: MobileTokens.space3),
          Text('Add forwarding rule',
              style: mobileHeading(size: 17)),
          const SizedBox(height: MobileTokens.space3),
          // Type selector
          SegmentedButton<ForwardType>(
            segments: const [
              ButtonSegment(value: ForwardType.local, label: Text('Local')),
              ButtonSegment(value: ForwardType.remote, label: Text('Remote')),
              ButtonSegment(
                  value: ForwardType.dynamic, label: Text('Dynamic')),
            ],
            selected: {_type},
            onSelectionChanged: (s) =>
                setState(() {
                  _type = s.first;
                  _validationError = null;
                }),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? MobileColors.accent
                      : MobileColors.surface),
              foregroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? MobileColors.bg
                      : MobileColors.textMuted),
            ),
          ),
          const SizedBox(height: MobileTokens.space3),
          _field('Label (optional)', _labelCtrl),
          const SizedBox(height: MobileTokens.space2),
          _field('Local port', _localPortCtrl,
              numeric: true,
              hint: _type == ForwardType.dynamic ? '1080' : '5432'),
          if (_type != ForwardType.dynamic) ...[
            const SizedBox(height: MobileTokens.space2),
            _field('Remote host', _remoteHostCtrl, hint: 'db-server'),
            const SizedBox(height: MobileTokens.space2),
            _field('Remote port', _remotePortCtrl,
                numeric: true, hint: '5432'),
          ],
          const SizedBox(height: MobileTokens.space4),
          if (_validationError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: MobileTokens.space3),
              child: Text(
                _validationError!,
                style: mobileBody(size: 13, color: MobileColors.red),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: MobileColors.accent,
                foregroundColor: MobileColors.bg,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(MobileTokens.radiusCard),
                ),
              ),
              onPressed: _save,
              child: Text('Add rule',
                  style: mobileBody(
                      size: 15,
                      weight: FontWeight.w600,
                      color: MobileColors.bg)),
            ),
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
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      inputFormatters:
          numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: mobileBody(size: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: mobileBody(size: 13, color: MobileColors.textMuted),
        hintStyle: mobileBody(size: 14, color: MobileColors.textFaint),
        filled: true,
        fillColor: MobileColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: MobileTokens.space3,
          vertical: MobileTokens.space3,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MobileTokens.radiusField),
          borderSide: const BorderSide(color: MobileColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MobileTokens.radiusField),
          borderSide: const BorderSide(color: MobileColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MobileTokens.radiusField),
          borderSide:
              const BorderSide(color: MobileColors.accent, width: 1.5),
        ),
      ),
    );
  }
}
