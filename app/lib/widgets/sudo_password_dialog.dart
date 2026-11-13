import 'package:flutter/material.dart';

import '../models/host.dart';

import 'package:yourssh_ui/yourssh_ui.dart';

/// Prompts for the sudo password used by elevated SFTP. Pops with
/// `(password:, remember:)` on OK, or null when cancelled. Persisting the
/// password (when remember is checked) is the caller's job.
class SudoPasswordDialog extends StatefulWidget {
  final Host host;
  const SudoPasswordDialog({super.key, required this.host});

  @override
  State<SudoPasswordDialog> createState() => _SudoPasswordDialogState();
}

class _SudoPasswordDialogState extends State<SudoPasswordDialog> {
  final _controller = TextEditingController();
  bool _remember = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.isEmpty) return;
    Navigator.of(context)
        .pop((password: _controller.text, remember: _remember));
  }

  @override
  Widget build(BuildContext context) {
    return YsDialog(
      title: 'Sudo password',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Root SFTP on ${widget.host.username}@${widget.host.host} '
            'needs the sudo password.',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: YsSpace.s3),
          FTextField(
            control: FTextFieldControl.managed(controller: _controller),
            label: const Text('Password'),
            obscureText: true,
            autofocus: true,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onSubmit: (_) => _submit(),
          ),
          const SizedBox(height: YsSpace.s2),
          FCheckbox(
            value: _remember,
            onChange: (v) => setState(() => _remember = v),
            label: const Text('Remember in system keychain'),
          ),
        ],
      ),
      actions: [
        FButton(
          variant: FButtonVariant.outline,
          onPress: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FButton(
          variant: FButtonVariant.primary,
          onPress: _submit,
          child: const Text('OK'),
        ),
      ],
    );
  }
}
