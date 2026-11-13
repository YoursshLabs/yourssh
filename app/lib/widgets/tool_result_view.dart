import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/tool_result.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import 'ys_form_controls.dart';

class ToolResultView extends StatelessWidget {
  final ToolResult? result;
  final bool isLoading;

  const ToolResultView({super.key, this.result, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: FCircularProgress());
    }
    if (result == null) {
      return const Center(
        child: Text(
          'Run a tool to see output',
          style: TextStyle(color: YsColors.mutedForeground),
        ),
      );
    }

    final color = result!.isSuccess ? YsColors.ok : YsColors.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: YsSpace.s3,
            vertical: YsSpace.s1,
          ),
          color: YsColors.sidebar,
          child: Row(
            children: [
              Icon(
                result!.isSuccess
                    ? FLucideIcons.circleCheck
                    : FLucideIcons.circleAlert,
                size: 14,
                color: color,
              ),
              const SizedBox(width: YsSpace.s2),
              Expanded(
                child: Text(
                  result!.isSuccess
                      ? 'Success (${result!.durationMs}ms)'
                      : 'Error',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 12),
                ),
              ),
              SettingsIconButton(
                icon: FLucideIcons.copy,
                tooltip: 'Copy output',
                onPress: () {
                  Clipboard.setData(
                    ClipboardData(text: result!.output ?? result!.error ?? ''),
                  );
                  showYsToast(
                    context,
                    'Copied',
                    duration: const Duration(seconds: 1),
                  );
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(YsSpace.s3),
            child: SelectableText(
              result!.output ?? result!.error ?? '',
              style: const TextStyle(
                color: YsColors.foreground,
                fontFamily: kYsMonoFontFamily,
                fontFamilyFallback: kYsMonoFontFallback,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
