import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class UtilityTools extends StatefulWidget {
  const UtilityTools({super.key});
  @override
  State<UtilityTools> createState() => _UtilityToolsState();
}
class _UtilityToolsState extends State<UtilityTools> {
  @override
  Widget build(BuildContext context) => const Center(
        child: Text('Utilities – coming in Task 4',
            style: TextStyle(color: AppColors.textSecondary)));
}
