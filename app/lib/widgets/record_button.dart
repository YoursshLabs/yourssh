import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

    return Tooltip(
      message: isRecording ? 'Stop recording' : 'Start recording',
      child: GestureDetector(
        onTap: () {
          if (isRecording) {
            provider.stopRecording(session.id);
          } else {
            provider.startRecording(session);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isRecording
                  ? Colors.red.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isRecording
                    ? Icons.stop_circle_outlined
                    : Icons.fiber_manual_record,
                size: 12,
                color: isRecording
                    ? Colors.red
                    : Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 4),
              Text(
                'REC',
                style: TextStyle(
                  color: isRecording
                      ? Colors.red
                      : Colors.white.withValues(alpha: 0.5),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
