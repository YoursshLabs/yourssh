import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/terminal_themes.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

class ThemePickerButton extends StatelessWidget {
  final String currentTheme;
  final ValueChanged<String> onChanged;

  const ThemePickerButton({
    super.key,
    required this.currentTheme,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final entry = kTerminalThemes.firstWhere(
      (e) => e.name == currentTheme,
      orElse: () => kTerminalThemes.first,
    );

    return FButton(
      variant: .ghost,
      size: .sm,
      mainAxisSize: MainAxisSize.min,
      onPress: () => _openPicker(context),
      prefix: _MiniSwatch(entry: entry, size: 18),
      suffix: const Icon(FLucideIcons.chevronDown),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 120),
        child: Text(currentTheme, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  void _openPicker(BuildContext context) {
    showYsDialog<String>(
      context,
      builder: (ctx) => _ThemePickerDialog(
        currentTheme: currentTheme,
        onSelected: (name) {
          Navigator.of(ctx).pop();
          onChanged(name);
        },
      ),
    );
  }
}

class _ThemePickerDialog extends StatefulWidget {
  final String currentTheme;
  final ValueChanged<String> onSelected;

  const _ThemePickerDialog({required this.currentTheme, required this.onSelected});

  @override
  State<_ThemePickerDialog> createState() => _ThemePickerDialogState();
}

class _ThemePickerDialogState extends State<_ThemePickerDialog> {
  @override
  Widget build(BuildContext context) {
    return YsDialogFrame(
      maxWidth: 580,
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: 580,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            const FDivider(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: kTerminalThemes.map((entry) {
                    final isSelected = entry.name == widget.currentTheme;
                    return _ThemeCard(
                      entry: entry,
                      isSelected: isSelected,
                      onTap: () => widget.onSelected(entry.name),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Row(
        children: [
          const Text(
            'Terminal Theme',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            '${kTerminalThemes.length} themes',
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Close',
            child: FButton.icon(
              variant: .ghost,
              size: .sm,
              onPress: () => Navigator.of(context).pop(),
              child: const Icon(FLucideIcons.x),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final TerminalThemeEntry entry;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeCard({
    required this.entry,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent.withValues(alpha: 0.12) : AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ColorPreview(entry: entry),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.name,
                      style: TextStyle(
                        color: isSelected ? AppColors.accent : AppColors.textPrimary,
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSelected)
                    const Icon(FLucideIcons.circleCheck, size: 12, color: AppColors.accent),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorPreview extends StatelessWidget {
  final TerminalThemeEntry entry;

  const _ColorPreview({required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = entry.data;
    final accentColors = [t.red, t.green, t.yellow, t.blue, t.magenta, t.cyan];

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
      child: Container(
        height: 48,
        color: t.background,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _dot(t.foreground.withValues(alpha: 0.5), 5),
                const SizedBox(width: 3),
                Expanded(
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: t.foreground.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: accentColors
                  .map((c) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: _dot(c, 7),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _MiniSwatch extends StatelessWidget {
  final TerminalThemeEntry entry;
  final double size;

  const _MiniSwatch({required this.entry, required this.size});

  @override
  Widget build(BuildContext context) {
    final t = entry.data;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: size * 1.6,
        height: size,
        child: Row(
          // Stretch: a child-less ColoredBox sizes to constraints.smallest,
          // so without tight height it lays out 0px tall and paints nothing.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: ColoredBox(color: t.background)),
            Expanded(child: ColoredBox(color: t.red)),
            Expanded(child: ColoredBox(color: t.green)),
            Expanded(child: ColoredBox(color: t.blue)),
          ],
        ),
      ),
    );
  }
}
