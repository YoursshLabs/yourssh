import 'package:flutter/widgets.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../../widgets/wt_widgets.dart';
import 'models.dart';

/// Editable list of key/value rows with an enable checkbox and a remove
/// button; a new empty row is appended when the last one gets a key.
class KvEditor extends StatelessWidget {
  final List<KvPair> pairs;
  final String keyHint;
  final String valueHint;
  final ValueChanged<List<KvPair>> onChange;

  const KvEditor({
    super.key,
    required this.pairs,
    required this.keyHint,
    required this.valueHint,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: YsColors.background,
      child: ListView.builder(
        padding: const EdgeInsets.all(YsSpace.s2),
        itemCount: pairs.length,
        itemBuilder: (_, i) {
          return KvRow(
            pair: pairs[i],
            keyHint: keyHint,
            valueHint: valueHint,
            onChanged: (p) {
              final updated = List<KvPair>.from(pairs);
              updated[i] = p;
              if (i == pairs.length - 1 && p.key.isNotEmpty) {
                updated.add(KvPair('', ''));
              }
              onChange(updated);
            },
            onRemove: pairs.length > 1
                ? () {
                    final updated = List<KvPair>.from(pairs)..removeAt(i);
                    onChange(updated);
                  }
                : null,
          );
        },
      ),
    );
  }
}

class KvRow extends StatefulWidget {
  final KvPair pair;
  final String keyHint;
  final String valueHint;
  final ValueChanged<KvPair> onChanged;
  final VoidCallback? onRemove;

  const KvRow({
    super.key,
    required this.pair,
    required this.keyHint,
    required this.valueHint,
    required this.onChanged,
    this.onRemove,
  });

  @override
  State<KvRow> createState() => _KvRowState();
}

class _KvRowState extends State<KvRow> {
  late final TextEditingController _keyCtrl;
  late final TextEditingController _valCtrl;
  final _keyFocus = FocusNode();
  final _valFocus = FocusNode();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController(text: widget.pair.key);
    _valCtrl = TextEditingController(text: widget.pair.value);
  }

  @override
  void didUpdateWidget(KvRow old) {
    super.didUpdateWidget(old);
    // Reflect external changes (URL <-> params sync) unless the user is typing
    // in that very cell.
    _syncing = true;
    try {
      if (!_keyFocus.hasFocus &&
          old.pair.key != widget.pair.key &&
          _keyCtrl.text != widget.pair.key) {
        wtSetText(_keyCtrl, widget.pair.key);
      }
      if (!_valFocus.hasFocus &&
          old.pair.value != widget.pair.value &&
          _valCtrl.text != widget.pair.value) {
        wtSetText(_valCtrl, widget.pair.value);
      }
    } finally {
      _syncing = false;
    }
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _valCtrl.dispose();
    _keyFocus.dispose();
    _valFocus.dispose();
    super.dispose();
  }

  // The managed text field also reports selection-only and programmatic
  // changes; only a real text edit reaches the parent.
  void _notify(String _) {
    if (_syncing) return;
    if (_keyCtrl.text == widget.pair.key && _valCtrl.text == widget.pair.value) {
      return;
    }
    widget.onChanged(
      KvPair(_keyCtrl.text, _valCtrl.text, enabled: widget.pair.enabled),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: YsSpace.s1),
      child: Row(
        children: [
          FCheckbox(
            semanticsLabel: 'Enabled',
            value: widget.pair.enabled,
            onChange: (_) => widget.onChanged(
              KvPair(
                widget.pair.key,
                widget.pair.value,
                enabled: !widget.pair.enabled,
              ),
            ),
          ),
          const SizedBox(width: YsSpace.s2),
          Expanded(
            child: WtField(
              controller: _keyCtrl,
              focusNode: _keyFocus,
              hint: widget.keyHint,
              onChanged: _notify,
            ),
          ),
          const SizedBox(width: YsSpace.s1),
          Expanded(
            child: WtField(
              controller: _valCtrl,
              focusNode: _valFocus,
              hint: widget.valueHint,
              onChanged: _notify,
            ),
          ),
          const SizedBox(width: YsSpace.s1),
          SizedBox(
            width: 28,
            child: widget.onRemove != null
                ? WtIconButton(
                    icon: FLucideIcons.x,
                    tooltip: 'Remove row',
                    onPress: widget.onRemove,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
