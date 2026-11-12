import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Background of the selected suggestion row (amber selection tint).
const Color kSuggestionSelectedColor = Color(0x29F3A231); // primary @ 16%

/// Command / path completion list shown by the terminal and the input bar.
/// At most 8 rows; tap a row to pick it. Plain token-styled rows (no
/// per-row state), so rebuilding it on each keystroke stays as cheap as
/// before.
class SuggestionPopup extends StatelessWidget {
  final List<String> suggestions;
  final int selectedIndex;
  final void Function(String) onSelect;
  final double maxHeight;

  const SuggestionPopup({
    super.key,
    required this.suggestions,
    required this.selectedIndex,
    required this.onSelect,
    this.maxHeight = 160,
  });

  @override
  Widget build(BuildContext context) {
    final items = suggestions.take(8).toList();
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: YsColors.card,
        border: Border.all(color: YsColors.border),
        borderRadius: BorderRadius.circular(YsRadius.control),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: YsSpace.s1),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final selected = i == selectedIndex;
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(items[i]),
              child: Container(
                decoration: BoxDecoration(
                  color: selected ? kSuggestionSelectedColor : Colors.transparent,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: YsSpace.s3,
                  vertical: YsSpace.s1 + 2,
                ),
                child: Text(
                  items[i],
                  style: TextStyle(
                    color: selected ? YsColors.accentText : YsColors.foreground,
                    fontFamily: kYsMonoFontFamily,
                    fontFamilyFallback: kYsMonoFontFallback,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
