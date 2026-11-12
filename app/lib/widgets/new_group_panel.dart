import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../providers/host_provider.dart';

class NewGroupPanel extends StatefulWidget {
  final VoidCallback onClose;
  const NewGroupPanel({super.key, required this.onClose});

  @override
  State<NewGroupPanel> createState() => _NewGroupPanelState();
}

class _NewGroupPanelState extends State<NewGroupPanel> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Group name is required');
      return;
    }
    final provider = context.read<HostProvider>();
    final exists = provider.pinnedGroups.any(
      (g) => g.toLowerCase() == name.toLowerCase(),
    );
    if (exists) {
      setState(() => _error = 'Group "$name" already exists');
      return;
    }
    setState(() { _saving = true; _error = null; });
    await provider.addGroup(name);
    if (mounted) widget.onClose();
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
        children: [
          _buildHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  YsSpace.s4, YsSpace.s4, YsSpace.s4, YsSpace.s5),
              children: [
                FTextField(
                  key: const Key('new-group-name'),
                  control: FTextFieldControl.managed(controller: _ctrl),
                  autofocus: true,
                  hint: 'Group name',
                  error: _error == null ? null : Text(_error!),
                  textInputAction: TextInputAction.done,
                  onSubmit: (_) => _save(),
                  prefixBuilder: (context, style, variants) =>
                      FTextField.prefixIconBuilder(context, style, variants,
                          const Icon(FLucideIcons.folder)),
                ),
                const SizedBox(height: YsSpace.s5),
                FButton(
                  onPress: _saving ? null : _save,
                  child: _saving
                      ? const FCircularProgress(size: .sm)
                      : const Text('Save group'),
                ),
              ],
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
        border: Border(bottom: BorderSide(color: YsColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: YsSpace.s4),
      child: Row(
        children: [
          const Expanded(
            child: Text('New group',
                style: TextStyle(
                    color: YsColors.foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ),
          Tooltip(
            message: 'Close',
            child: FButton.icon(
              variant: .ghost,
              size: .sm,
              onPress: widget.onClose,
              child: const Icon(FLucideIcons.x),
            ),
          ),
        ],
      ),
    );
  }
}
