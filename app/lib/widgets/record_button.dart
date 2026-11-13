import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../models/terminal_session.dart';
import '../providers/recording_provider.dart';

/// Floating REC toggle shown over a terminal pane (SSH and local).
class RecordButton extends StatelessWidget {
  final TerminalSession session;
  const RecordButton({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecordingProvider>();
    final isRecording = provider.isRecording(session.id);
    final fg = isRecording ? YsColors.error : YsColors.mutedForeground;

    return Tooltip(
      message: isRecording ? 'Stop recording' : 'Start recording',
      child: DecoratedBox(
        // Opaque-ish chrome so the toggle stays readable over terminal text.
        decoration: BoxDecoration(
          color: YsColors.card.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(YsRadius.control),
          border: Border.all(
            color: isRecording
                ? YsColors.error.withValues(alpha: 0.6)
                : YsColors.border,
          ),
        ),
        child: FButton(
          key: const Key('record-button'),
          variant: .ghost,
          size: .xs,
          mainAxisSize: MainAxisSize.min,
          onPress: () {
            if (isRecording) {
              provider.stopRecording(session.id);
            } else {
              provider.startRecording(session);
            }
          },
          prefix: Icon(
            isRecording ? FLucideIcons.circleStop : FLucideIcons.circleDot,
            size: 12,
            color: fg,
          ),
          child: Text(
            'REC',
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
