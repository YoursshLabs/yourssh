import 'package:flutter/widgets.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../../widgets/wt_widgets.dart';
import 'models.dart';

/// Slide-over list of the last requests; selecting a row reloads it.
class HttpHistoryPanel extends StatelessWidget {
  final List<HistoryItem> history;
  final ValueChanged<HistoryItem> onSelect;
  final VoidCallback onClose;

  const HttpHistoryPanel({
    super.key,
    required this.history,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: YsColors.sidebar,
        border: Border(right: BorderSide(color: YsColors.border)),
        boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 12)],
      ),
      child: Column(
        children: [
          Container(
            color: YsColors.card,
            padding: const EdgeInsets.fromLTRB(
              YsSpace.s3 + 2,
              YsSpace.s1,
              YsSpace.s2,
              YsSpace.s1,
            ),
            child: Row(
              children: [
                const Text(
                  'History',
                  style: TextStyle(
                    color: YsColors.foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                WtIconButton(
                  icon: FLucideIcons.x,
                  tooltip: 'Close history',
                  onPress: onClose,
                ),
              ],
            ),
          ),
          const FDivider(),
          if (history.isEmpty)
            const Expanded(child: WtHint('No history yet'))
          else
            Expanded(
              child: ListView.separated(
                itemCount: history.length,
                separatorBuilder: (_, _) => const FDivider(),
                itemBuilder: (_, i) => _HistoryRow(
                  item: history[i],
                  onTap: () => onSelect(history[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final HistoryItem item;
  final VoidCallback onTap;
  const _HistoryRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FTappable(
      semanticsLabel: '${item.method} ${item.url}',
      onPress: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: YsSpace.s3,
          vertical: YsSpace.s3 - 2,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 54,
              child: Text(
                item.method,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: methodColor(item.method),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: Text(
                item.url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: YsColors.foreground,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(width: YsSpace.s2),
            Text(
              item.statusCode == 0 ? 'ERR' : '${item.statusCode}',
              style: TextStyle(
                color: statusColor(item.statusCode),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${item.durationMs}ms',
              style: const TextStyle(
                color: YsColors.mutedForeground,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
