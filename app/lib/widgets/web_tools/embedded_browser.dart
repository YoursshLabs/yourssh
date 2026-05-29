import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class EmbeddedBrowser extends StatefulWidget {
  final String? initialUrl;
  const EmbeddedBrowser({super.key, this.initialUrl});

  @override
  State<EmbeddedBrowser> createState() => _EmbeddedBrowserState();
}

class _EmbeddedBrowserState extends State<EmbeddedBrowser> {
  @override
  Widget build(BuildContext context) => const Center(
        child: Text('Browser – coming in Task 2',
            style: TextStyle(color: AppColors.textSecondary)),
      );
}
