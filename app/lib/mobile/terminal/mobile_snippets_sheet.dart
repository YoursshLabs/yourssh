import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_snippets/yourssh_snippets.dart';

import '../../theme/app_theme.dart';

/// Bottom-sheet list of snippets; tapping one inserts its command into the
/// active terminal (via [onInsert]) and closes the sheet.
class MobileSnippetsSheet extends StatefulWidget {
  final void Function(String command) onInsert;
  const MobileSnippetsSheet({super.key, required this.onInsert});

  @override
  State<MobileSnippetsSheet> createState() => _MobileSnippetsSheetState();
}

class _MobileSnippetsSheetState extends State<MobileSnippetsSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = context.watch<SnippetProvider>().snippets;
    final shown = filterSnippets(all, _query);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Search snippets',
                prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: shown.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No snippets',
                          style: TextStyle(color: AppColors.textSecondary)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final s = shown[i];
                        return ListTile(
                          title: Text(s.label,
                              style:
                                  const TextStyle(color: AppColors.textPrimary)),
                          subtitle: Text(s.command,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  fontFamily: 'monospace')),
                          onTap: () {
                            widget.onInsert(s.command);
                            Navigator.of(context).pop();
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
