import 'package:flutter/widgets.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../../widgets/wt_widgets.dart';
import 'kv_editor.dart';
import 'models.dart';

class BodyPanel extends StatelessWidget {
  final BodyType bodyType;
  final TextEditingController bodyCtrl;
  final List<KvPair> formPairs;
  final bool hasBody;
  final ValueChanged<BodyType> onBodyTypeChanged;
  final ValueChanged<List<KvPair>> onFormPairsChanged;

  const BodyPanel({
    super.key,
    required this.bodyType,
    required this.bodyCtrl,
    required this.formPairs,
    required this.hasBody,
    required this.onBodyTypeChanged,
    required this.onFormPairsChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasBody) {
      return const WtHint('Body not applicable for this method');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: YsColors.sidebar,
          padding: const EdgeInsets.symmetric(
            horizontal: YsSpace.s3,
            vertical: YsSpace.s2,
          ),
          child: Wrap(
            spacing: YsSpace.s2,
            runSpacing: YsSpace.s1,
            children: [
              WtChip(
                label: 'JSON',
                selected: bodyType == BodyType.raw,
                onTap: () => onBodyTypeChanged(BodyType.raw),
              ),
              WtChip(
                label: 'URL Encoded',
                selected: bodyType == BodyType.urlEncoded,
                onTap: () => onBodyTypeChanged(BodyType.urlEncoded),
              ),
              WtChip(
                label: 'None',
                selected: bodyType == BodyType.none,
                onTap: () => onBodyTypeChanged(BodyType.none),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (bodyType) {
            BodyType.raw => ColoredBox(
              color: YsColors.background,
              child: Padding(
                padding: const EdgeInsets.all(YsSpace.s3),
                child: WtCodeArea(
                  key: const ValueKey('http-body'),
                  controller: bodyCtrl,
                  hint: '{ "key": "value" }',
                ),
              ),
            ),
            BodyType.urlEncoded => KvEditor(
              pairs: formPairs,
              keyHint: 'Key',
              valueHint: 'Value',
              onChange: onFormPairsChanged,
            ),
            BodyType.none => const WtHint('No body'),
          },
        ),
      ],
    );
  }
}
