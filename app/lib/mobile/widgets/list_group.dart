import 'package:flutter/material.dart';
import '../theme/mobile_theme.dart';
import '../theme/mobile_tokens.dart';

/// iOS-style grouped container with hairline dividers between children
/// and an optional uppercase section label above.
class ListGroup extends StatelessWidget {
  final List<Widget> children;
  final String? label;

  const ListGroup({super.key, required this.children, this.label});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(const Divider(
          height: 1,
          thickness: 0.5,
          indent: 15,
          endIndent: 0,
          color: MobileColors.border,
        ));
      }
    }

    final grouped = Container(
      decoration: BoxDecoration(
        color: MobileColors.surface,
        borderRadius: BorderRadius.circular(MobileTokens.radiusCard),
        border: Border.all(color: MobileColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );

    if (label == null) return grouped;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: MobileTokens.space1,
            bottom: MobileTokens.sectionLabelGap,
          ),
          child: Text(label!.toUpperCase(), style: MobileTokens.sectionLabel()),
        ),
        grouped,
      ],
    );
  }
}
