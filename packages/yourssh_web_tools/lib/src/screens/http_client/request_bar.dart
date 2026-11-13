import 'package:flutter/widgets.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../../widgets/wt_widgets.dart';
import 'models.dart';

/// Method select, URL field, history toggle and Send button.
class RequestBar extends StatelessWidget {
  final String method;
  final List<String> methods;
  final TextEditingController urlCtrl;
  final bool loading;
  final int historyCount;
  final ValueChanged<String> onMethodChanged;
  final VoidCallback onSend;
  final VoidCallback onToggleHistory;

  const RequestBar({
    super.key,
    required this.method,
    required this.methods,
    required this.urlCtrl,
    required this.loading,
    required this.historyCount,
    required this.onMethodChanged,
    required this.onSend,
    required this.onToggleHistory,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: YsColors.sidebar,
        border: Border(bottom: BorderSide(color: YsColors.border)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: YsSpace.s4,
        vertical: YsSpace.s2,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 128,
            child: FSelect<String>.rich(
              key: const ValueKey('http-method-select'),
              size: .sm,
              control: .lifted(
                value: method,
                onChange: (m) {
                  if (m != null) onMethodChanged(m);
                },
              ),
              format: (m) => m,
              prefixBuilder: (context, style, variants) => Padding(
                padding: const EdgeInsets.only(left: YsSpace.s3),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: methodColor(method),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              children: [
                for (final m in methods)
                  FSelectItem<String>(
                    title: Text(m, style: TextStyle(color: methodColor(m))),
                    value: m,
                  ),
              ],
            ),
          ),
          const SizedBox(width: YsSpace.s2),
          Expanded(
            child: WtField(
              key: const ValueKey('http-url'),
              controller: urlCtrl,
              mono: false,
              hint: 'https://api.example.com/endpoint',
              onSubmit: (_) => onSend(),
            ),
          ),
          const SizedBox(width: YsSpace.s2),
          Stack(
            clipBehavior: Clip.none,
            children: [
              WtIconButton(
                buttonKey: const ValueKey('http-history'),
                icon: FLucideIcons.history,
                tooltip: 'Request history',
                onPress: onToggleHistory,
              ),
              if (historyCount > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: YsColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          historyCount > 9 ? '9+' : '$historyCount',
                          style: const TextStyle(
                            color: YsColors.primaryForeground,
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: YsSpace.s2),
          IntrinsicWidth(
            child: FButton(
              key: const ValueKey('http-send'),
              size: .sm,
              mainAxisSize: .min,
              onPress: loading ? null : onSend,
              child: loading
                  ? const FCircularProgress(size: .sm)
                  : const Text('Send'),
            ),
          ),
        ],
      ),
    );
  }
}
