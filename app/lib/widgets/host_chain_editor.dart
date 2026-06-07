import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/host.dart';
import '../services/os_detection.dart';
import '../theme/app_theme.dart';

/// Termius-style visual chain editor for a multi-hop jump chain.
///
/// Pure presentational: data in via constructor, the only output is
/// [onChanged] — the full ordered hop-id list after any add/remove/clear.
/// Spec: docs/superpowers/specs/2026-06-07-multi-hop-jump-chain-design.md
class HostChainEditor extends StatelessWidget {
  /// Label of the host being edited (bottom card / helper text).
  final String currentHostLabel;

  /// detectedOs of the host being edited (null → generic glyph).
  final String? currentHostOs;

  /// Ordered jump chain (bastion → … ); empty = direct.
  final List<Host> chain;

  /// Shows the key glyph on the LAST hop when agent forwarding is on
  /// (forwarding terminates at the destination, served via the final hop).
  final bool agentForwarding;

  /// Hosts selectable as a hop (caller excludes the edited host).
  final List<Host> candidates;

  /// Fires the full ordered id list after any add/remove/clear.
  final ValueChanged<List<String>> onChanged;

  const HostChainEditor({
    super.key,
    required this.currentHostLabel,
    this.currentHostOs,
    this.chain = const [],
    this.agentForwarding = false,
    required this.candidates,
    required this.onChanged,
  });

  Future<void> _addHop(BuildContext context) async {
    final chosen = chain.map((h) => h.id).toSet();
    final pickable =
        candidates.where((h) => !chosen.contains(h.id)).toList();
    final picked = await showDialog<Host>(
      context: context,
      builder: (_) => _HostPickerDialog(candidates: pickable),
    );
    if (picked != null) onChanged([...chain.map((h) => h.id), picked.id]);
  }

  void _removeAt(int i) {
    final ids = chain.map((h) => h.id).toList()..removeAt(i);
    onChanged(ids);
  }

  @override
  Widget build(BuildContext context) {
    return chain.isEmpty ? _emptyState(context) : _chainView(context);
  }

  Widget _emptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            TextSpan(
              text: 'Adding a host will route the connection to ',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
              children: [
                TextSpan(
                  text: currentHostLabel,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _actionButton(
            label: 'Add a Host',
            color: AppColors.textPrimary,
            bg: AppColors.cardHover,
            onTap: () => _addHop(context),
          ),
        ],
      ),
    );
  }

  Widget _chainView(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < chain.length; i++) {
      final hop = chain[i];
      if (i > 0) rows.add(_arrow());
      final isLast = i == chain.length - 1;
      rows.add(_HostCard(
        label: hop.label.isNotEmpty ? hop.label : '${hop.username}@${hop.host}',
        detectedOs: hop.detectedOs,
        trailing: (agentForwarding && isLast)
            ? const Tooltip(
                message:
                    'Agent forwarding on — the destination uses your local keys',
                child: Icon(Icons.key, size: 14, color: AppColors.accent),
              )
            : _RemoveButton(onTap: () => _removeAt(i)),
      ));
    }
    rows.add(_arrow());
    rows.add(_HostCard(label: currentHostLabel, detectedOs: currentHostOs));
    rows.add(const SizedBox(height: 10));
    rows.add(_actionButton(
      label: 'Add a Host',
      color: AppColors.textPrimary,
      bg: AppColors.cardHover,
      onTap: () => _addHop(context),
    ));
    rows.add(const SizedBox(height: 6));
    rows.add(_actionButton(
      label: 'Clear',
      color: AppColors.red,
      bg: AppColors.red.withValues(alpha: 0.12),
      onTap: () => onChanged(const []),
    ));
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  Widget _arrow() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Icon(Icons.arrow_downward,
            size: 16, color: AppColors.textTertiary),
      );

  Widget _actionButton({
    required String label,
    required Color color,
    required Color bg,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 32,
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

/// Hover/tap × to drop one hop from the chain.
class _RemoveButton extends StatelessWidget {
  final VoidCallback onTap;
  const _RemoveButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: const Tooltip(
          message: 'Remove hop',
          child: Icon(Icons.close, size: 14, color: AppColors.textTertiary),
        ),
      ),
    );
  }
}

/// One host row in the chain: OS glyph tile + label (+ optional trailing).
class _HostCard extends StatelessWidget {
  final String label;
  final String? detectedOs;
  final Widget? trailing;

  const _HostCard({
    required this.label,
    this.detectedOs,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final asset = osIconAsset(detectedOs);
    return RepaintBoundary(
      child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.cardHover,
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: asset != null
                    ? SvgPicture.asset(
                        asset,
                        width: 16,
                        height: 16,
                        colorFilter: const ColorFilter.mode(
                          AppColors.textPrimary,
                          BlendMode.srcIn,
                        ),
                      )
                    : const Icon(
                        Icons.dns_outlined,
                        size: 15,
                        color: AppColors.textSecondary,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
    );
  }
}

/// Searchable list of candidate jump hosts. Pops with the picked [Host].
class _HostPickerDialog extends StatefulWidget {
  final List<Host> candidates;
  const _HostPickerDialog({required this.candidates});

  @override
  State<_HostPickerDialog> createState() => _HostPickerDialogState();
}

class _HostPickerDialogState extends State<_HostPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.candidates
        : widget.candidates
              .where(
                (h) =>
                    h.label.toLowerCase().contains(q) ||
                    '${h.username}@${h.host}'.toLowerCase().contains(q),
              )
              .toList();
    return Dialog(
      backgroundColor: AppColors.sidebar,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  hintText: 'Search hosts…',
                  hintStyle: const TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 13,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 16),
                child: Text(
                  'No hosts found',
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final h = filtered[i];
                    return InkWell(
                      onTap: () => Navigator.of(context).pop(h),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              h.label.isNotEmpty
                                  ? h.label
                                  : '${h.username}@${h.host}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              '${h.username}@${h.host}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
