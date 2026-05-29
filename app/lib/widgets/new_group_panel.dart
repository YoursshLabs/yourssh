import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/host_provider.dart';
import '../theme/app_theme.dart';

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
        color: AppColors.sidebar,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _error != null ? AppColors.red : AppColors.border,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_outlined, size: 16, color: AppColors.textTertiary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            autofocus: true,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                            decoration: const InputDecoration(
                              hintText: 'Group name',
                              hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onSubmitted: (_) => _save(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 11)),
                ],
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: _saving ? null : _save,
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: _saving ? AppColors.accentDim : AppColors.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: _saving
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                        : const Text('SAVE GROUP',
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                letterSpacing: 1)),
                  ),
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
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Expanded(
            child: Text('New Group',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
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
}
