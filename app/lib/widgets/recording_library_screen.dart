// app/lib/widgets/recording_library_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/recording_entry.dart';
import '../providers/recording_provider.dart';
import '../theme/app_theme.dart';
import 'recording_player_widget.dart';

class RecordingLibraryScreen extends StatefulWidget {
  const RecordingLibraryScreen({super.key});

  @override
  State<RecordingLibraryScreen> createState() => _RecordingLibraryScreenState();
}

class _RecordingLibraryScreenState extends State<RecordingLibraryScreen> {
  RecordingEntry? _playing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RecordingProvider>().refreshLibrary();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: _playing != null ? 360 : double.infinity,
          child: _LibraryList(
            onPlay: (entry) => setState(() => _playing = entry),
            playingPath: _playing?.filePath,
          ),
        ),
        if (_playing != null) ...[
          const VerticalDivider(width: 1, color: AppColors.border),
          Expanded(
            child: Column(
              children: [
                _PlayerHeader(
                  entry: _playing!,
                  onClose: () => setState(() => _playing = null),
                ),
                Expanded(
                  child: RecordingPlayerWidget(
                    key: ValueKey(_playing!.filePath),
                    filePath: _playing!.filePath,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PlayerHeader extends StatelessWidget {
  final RecordingEntry entry;
  final VoidCallback onClose;
  const _PlayerHeader({required this.entry, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.play_circle_outline, size: 14, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.fileName,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 14, color: AppColors.textSecondary),
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _LibraryList extends StatelessWidget {
  final ValueChanged<RecordingEntry> onPlay;
  final String? playingPath;
  const _LibraryList({required this.onPlay, this.playingPath});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecordingProvider>();
    final groups = provider.groupedRecordings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              const Text('Recording Library',
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 14, color: AppColors.textSecondary),
                onPressed: () => provider.refreshLibrary(),
                visualDensity: VisualDensity.compact,
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        Expanded(
          child: groups.isEmpty
              ? const Center(
                  child: Text(
                    'No recordings yet.\nStart a session and press REC.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: groups.entries
                      .map((e) => _HostGroup(
                            hostTitle: e.key,
                            recordings: e.value,
                            onPlay: onPlay,
                            playingPath: playingPath,
                          ))
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class _HostGroup extends StatelessWidget {
  final String hostTitle;
  final List<RecordingEntry> recordings;
  final ValueChanged<RecordingEntry> onPlay;
  final String? playingPath;
  const _HostGroup({required this.hostTitle, required this.recordings, required this.onPlay, this.playingPath});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.dns_outlined, size: 12, color: AppColors.textTertiary),
              const SizedBox(width: 6),
              Text(hostTitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Text('${recordings.length} recording${recordings.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
            ],
          ),
        ),
        ...recordings.map((r) => _RecordingRow(
              entry: r,
              isPlaying: r.filePath == playingPath,
              onPlay: () => onPlay(r),
            )),
      ],
    );
  }
}

class _RecordingRow extends StatelessWidget {
  final RecordingEntry entry;
  final bool isPlaying;
  final VoidCallback onPlay;
  const _RecordingRow({required this.entry, required this.isPlaying, required this.onPlay});

  String _fmtSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '${bytes}B';
    return '${(bytes / 1024).round()} KB';
  }

  String _fmtDate(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: isPlaying ? AppColors.accent.withValues(alpha: 0.08) : Colors.transparent,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_fmtDate(entry.recordedAt),
                    style: TextStyle(
                      color: isPlaying ? AppColors.accent : AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: isPlaying ? FontWeight.w600 : FontWeight.normal,
                    )),
                if (entry.fileSize != null)
                  Text(_fmtSize(entry.fileSize),
                      style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(isPlaying ? Icons.play_circle : Icons.play_circle_outline,
                size: 18, color: isPlaying ? AppColors.accent : AppColors.textSecondary),
            onPressed: onPlay,
            tooltip: 'Play',
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.textTertiary),
            onPressed: () => _confirmDelete(context),
            tooltip: 'Delete',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.sidebar,
        title: const Text('Delete recording?', style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
        content: Text(entry.fileName, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<RecordingProvider>().deleteRecording(entry.filePath);
    }
  }
}
