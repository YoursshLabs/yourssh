import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../models/host.dart';

/// RDP password re-prompt. Pops the typed password on Enter or Connect, and
/// null on Cancel / Escape.
class RdpPasswordDialog extends StatefulWidget {
  final Host host;
  const RdpPasswordDialog({required this.host});

  @override
  State<RdpPasswordDialog> createState() => RdpPasswordDialogState();
}

class RdpPasswordDialogState extends State<RdpPasswordDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YsDialog(
      title: 'Password for ${widget.host.label}',
      body: FTextField.password(
        key: const Key('rdp-password'),
        control: FTextFieldControl.managed(controller: _ctrl),
        label: const Text('Password'),
        autofocus: true,
        autofillHints: const [],
        textInputAction: TextInputAction.done,
        onSubmit: (_) => Navigator.pop(context, _ctrl.text),
      ),
      actions: [
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FButton(
          variant: FButtonVariant.primary,
          onPress: () => Navigator.pop(context, _ctrl.text),
          child: const Text('Connect'),
        ),
      ],
    );
  }
}

