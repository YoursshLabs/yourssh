import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/tool_result.dart';
import '../theme/app_theme.dart';

class ToolResultView extends StatelessWidget {
  final ToolResult? result;
  final bool isLoading;

  const ToolResultView({super.key, this.result, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (result == null) {
      return const Center(
        child: Text('Run a tool to see output',
            style: TextStyle(color: AppColors.textTertiary)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: AppColors.sidebar,
          child: Row(
            children: [
              Icon(
                result!.isSuccess ? Icons.check_circle_outline : Icons.error_outline,
                size: 14,
                color: result!.isSuccess ? AppColors.accent : AppColors.red,
              ),
              const SizedBox(width: 6),
              Text(
                result!.isSuccess
                    ? 'Success (${result!.durationMs}ms)'
                    : 'Error',
                style: TextStyle(
                  color: result!.isSuccess ? AppColors.accent : AppColors.red,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 14, color: AppColors.textSecondary),
                tooltip: 'Copy output',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  Clipboard.setData(
                      ClipboardData(text: result!.output ?? result!.error ?? ''));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Copied'),
                        duration: Duration(seconds: 1)),
                  );
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              result!.output ?? result!.error ?? '',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontFamily: 'monospace',
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
