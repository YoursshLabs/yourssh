import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../models/host.dart';
import '../services/os_detection.dart';

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
    final pickable = candidates.where((h) => !chosen.contains(h.id)).toList();
    final picked = await showYsDialog<Host>(
      context,
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

  Widget _addButton(BuildContext context) => FButton(
    variant: .secondary,
    size: .sm,
    prefix: const Icon(FLucideIcons.plus),
    onPress: () => _addHop(context),
    child: const Text('Add a Host'),
  );

  Widget _emptyState(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: YsColors.card,
        borderRadius: BorderRadius.circular(YsRadius.card),
        border: Border.all(color: YsColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(YsSpace.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text.rich(
              TextSpan(
                text: 'Adding a host will route the connection to ',
                style: const TextStyle(
                  color: YsColors.mutedForeground,
                  fontSize: 12,
                  height: 1.4,
                ),
                children: [
                  TextSpan(
                    text: currentHostLabel,
                    style: const TextStyle(
                      color: YsColors.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: YsSpace.s3),
            _addButton(context),
          ],
        ),
      ),
    );
  }

  Widget _chainView(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < chain.length; i++) {
      final hop = chain[i];
      if (i > 0) rows.add(_arrow());
      final isLast = i == chain.length - 1;
      rows.add(
        _HostCard(
          label: hop.label.isNotEmpty
              ? hop.label
              : '${hop.username}@${hop.host}',
          detectedOs: hop.detectedOs,
          trailing: (agentForwarding && isLast)
              ? const Tooltip(
                  message: 'Agent forwarding on — the destination uses your local keys',
                  child: Icon(
                    FLucideIcons.keyRound,
                    size: 14,
                    color: YsColors.primary,
                  ),
                )
              : Tooltip(
                  message: 'Remove hop',
                  excludeFromSemantics: true,
                  child: FButton.icon(
                    variant: .ghost,
                    size: .xs,
                    semanticsLabel: 'Remove hop',
                    onPress: () => _removeAt(i),
                    child: const Icon(FLucideIcons.x),
                  ),
                ),
        ),
      );
    }
    rows.add(_arrow());
    rows.add(
      _HostCard(
        label: currentHostLabel,
        detectedOs: currentHostOs,
        destination: true,
      ),
    );
    rows.add(const SizedBox(height: YsSpace.s3));
    rows.add(_addButton(context));
    rows.add(const SizedBox(height: YsSpace.s2));
    rows.add(
      FButton(
        variant: .ghost,
        size: .sm,
        style: .delta(
          contentStyle: .delta(
            textStyle: .delta([.all(const .delta(color: YsColors.error))]),
          ),
        ),
        onPress: () => onChanged(const []),
        child: const Text('Clear'),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  Widget _arrow() => const Padding(
    padding: EdgeInsets.symmetric(vertical: YsSpace.s1),
    child: Icon(
      FLucideIcons.arrowDown,
      size: 16,
      color: YsColors.mutedForeground,
    ),
  );
}

/// One host row in the chain: OS glyph tile + label (+ optional trailing).
/// The destination (the host being edited) has the amber border.
class _HostCard extends StatelessWidget {
  final String label;
  final String? detectedOs;
  final Widget? trailing;
  final bool destination;

  const _HostCard({
    required this.label,
    this.detectedOs,
    this.trailing,
    this.destination = false,
  });

  @override
  Widget build(BuildContext context) {
    final asset = osIconAsset(detectedOs);
    return RepaintBoundary(
      child: Container(
        height: 44,
        padding: const EdgeInsets.only(left: 10, right: YsSpace.s1),
        decoration: BoxDecoration(
          color: YsColors.card,
          borderRadius: BorderRadius.circular(YsRadius.card),
          border: Border.all(
            color: destination ? YsColors.primary : YsColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: YsColors.secondary,
                borderRadius: BorderRadius.circular(YsRadius.control),
              ),
              alignment: Alignment.center,
              child: asset != null
                  ? SvgPicture.asset(
                      asset,
                      width: 16,
                      height: 16,
                      colorFilter: const ColorFilter.mode(
                        YsColors.foreground,
                        BlendMode.srcIn,
                      ),
                    )
                  : const Icon(
                      FLucideIcons.server,
                      size: 15,
                      color: YsColors.mutedForeground,
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: YsColors.foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (trailing != null)
              Padding(
                padding: const EdgeInsets.only(left: YsSpace.s1, right: 6),
                child: trailing,
              ),
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
    return YsDialogFrame(
      maxWidth: 360,
      padding: const EdgeInsets.all(YsSpace.s3),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FTextField(
              key: const ValueKey('host-picker-search'),
              autofocus: true,
              size: .sm,
              hint: 'Search hosts…',
              control: .managed(
                onChange: (v) => setState(() => _query = v.text),
              ),
              prefixBuilder: (context, style, variants) =>
                  FTextField.prefixIconBuilder(
                    context,
                    style,
                    variants,
                    const Icon(FLucideIcons.search),
                  ),
            ),
            const SizedBox(height: YsSpace.s2),
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  YsSpace.s1,
                  YsSpace.s1,
                  YsSpace.s1,
                  YsSpace.s2,
                ),
                child: Text(
                  'No hosts found',
                  style: TextStyle(
                    color: YsColors.mutedForeground,
                    fontSize: 12,
                  ),
                ),
              )
            else
              Flexible(
                child: FItemGroup(
                  maxHeight: 340,
                  children: [
                    for (final h in filtered)
                      FItem(
                        title: Text(
                          h.label.isNotEmpty
                              ? h.label
                              : '${h.username}@${h.host}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${h.username}@${h.host}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPress: () => Navigator.of(context).pop(h),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
