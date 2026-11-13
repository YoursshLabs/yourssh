import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/plugin_engine_provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

class PluginConsoleScreen extends StatelessWidget {
  final String pluginId;
  const PluginConsoleScreen({super.key, required this.pluginId});

  @override
  Widget build(BuildContext context) {
    final logs = context.watch<PluginEngineProvider>().logsFor(pluginId);

    return Scaffold(
      backgroundColor: YsColors.background,
      body: logs.isEmpty
          ? Center(
              child: Text(
                'No logs for $pluginId.',
                style: const TextStyle(color: YsColors.mutedForeground),
              ),
            )
          : ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(YsSpace.s2),
              itemCount: logs.length,
              itemBuilder: (_, i) {
                final entry = logs[logs.length - 1 - i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    entry,
                    style: TextStyle(
                      color: entry.contains('[ERROR]')
                          ? YsColors.error
                          : YsColors.foreground,
                      fontFamily: kYsMonoFontFamily,
                      fontFamilyFallback: kYsMonoFontFallback,
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
