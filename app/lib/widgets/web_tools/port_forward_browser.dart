import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class PortForwardBrowser extends StatefulWidget {
  const PortForwardBrowser({super.key});
  @override
  State<PortForwardBrowser> createState() => _PortForwardBrowserState();
}
class _PortForwardBrowserState extends State<PortForwardBrowser> {
  @override
  Widget build(BuildContext context) => const Center(
        child: Text('Port Tunnels – coming in Task 5',
            style: TextStyle(color: AppColors.textSecondary)));
}
