import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class HttpClientTool extends StatefulWidget {
  const HttpClientTool({super.key});
  @override
  State<HttpClientTool> createState() => _HttpClientToolState();
}
class _HttpClientToolState extends State<HttpClientTool> {
  @override
  Widget build(BuildContext context) => const Center(
        child: Text('HTTP Client – coming in Task 3',
            style: TextStyle(color: AppColors.textSecondary)));
}
