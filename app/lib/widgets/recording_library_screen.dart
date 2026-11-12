// app/lib/widgets/recording_library_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/recording_entry.dart';
import '../providers/recording_provider.dart';
import '../theme/app_theme.dart';
import 'recording_player_widget.dart';
import 'settings/settings_tiles.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

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
      if (!mounted) return;
      context.read<RecordingProvider>().refreshLibrary();
    });
  }

  @override
  Widget build(BuildContext context) {
    // No player open: the list fills the area via Expanded. Using
    // SizedBox(width: double.infinity) as a direct Row child resolves to an
    // infinite width during Row's measure pass, producing a render box with a
    // non-finite size that the mouse tracker cannot hit-test ("Cannot hit test
    // a render box with no size" + the `!_debugDuringDeviceUpdate` assertion).
    if (_playing == null) {
      return _LibraryList(
        onPlay: (entry) => setState(() => _playing = entry),
        playingPath: null,
      );
    }

    return Row(
      children: [
        SizedBox(
          width: 360,
          child: _LibraryList(
            onPlay: (entry) => setState(() => _playing = entry),
            playingPath: _playing!.filePath,
          ),
        ),
        const VerticalDivider(width: 1, color: YsColors.border),
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
      padding: const EdgeInsets.symmetric(horizontal: YsSpace.s3),
      decoration: const BoxDecoration(
        color: YsColors.sidebar,
        border: Border(bottom: BorderSide(color: YsColors.border)),
      ),
      child: Row(
        children: [
          const Icon(FLucideIcons.circlePlay, size: 14, color: YsColors.primary),
          const SizedBox(width: YsSpace.s2),
          Expanded(
            child: Text(
              entry.fileName,
              style: const TextStyle(color: YsColors.foreground, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SettingsIconButton(
            icon: FLucideIcons.x,
            tooltip: 'Close player',
            onPress: onClose,
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
          padding: const EdgeInsets.symmetric(horizontal: YsSpace.s4),
          alignment: Alignment.centerLeft,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: YsColors.border)),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Recording Library',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: YsColors.foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SettingsIconButton(
                icon: FLucideIcons.refreshCw,
                tooltip: 'Refresh',
                onPress: () => provider.refreshLibrary(),
              ),
            ],
          ),
        ),
        Expanded(
          child: groups.isEmpty
              ? const YsEmptyState(
                  icon: FLucideIcons.clapperboard,
                  title: 'No recordings yet',
                  message: 'Start a session and press REC.',
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(
                    vertical: YsSpace.s2,
                    horizontal: YsSpace.s3,
                  ),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(YsSpace.s1, YsSpace.s3, YsSpace.s1, YsSpace.s1),
          child: Row(
            children: [
              const Icon(FLucideIcons.server, size: 12, color: YsColors.mutedForeground),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  hostTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: YsColors.mutedForeground,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFamily: kYsMonoFontFamily,
                    fontFamilyFallback: kYsMonoFontFallback,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${recordings.length} recording${recordings.length == 1 ? '' : 's'}',
                maxLines: 1,
                style: const TextStyle(color: YsColors.mutedForeground, fontSize: 11),
              ),
            ],
          ),
        ),
        settingsTileGroup(
          children: [
            for (final r in recordings)
              _recordingTile(context, r, r.filePath == playingPath, () => onPlay(r)),
          ],
        ),
      ],
    );
  }
}

String _fmtSize(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '${bytes}B';
  return '${(bytes / 1024).round()} KB';
}

String _pad(int n) => n.toString().padLeft(2, '0');

String _fmtDate(DateTime dt) =>
    '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} ${_pad(dt.hour)}:${_pad(dt.minute)}';

FTile _recordingTile(
  BuildContext context,
  RecordingEntry entry,
  bool isPlaying,
  VoidCallback onPlay,
) {
  return FTile.raw(
    selected: isPlaying,
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _fmtDate(entry.recordedAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isPlaying ? YsColors.accentText : YsColors.foreground,
                  fontSize: 12,
                  fontWeight: isPlaying ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (entry.fileSize != null)
                Text(
                  _fmtSize(entry.fileSize),
                  maxLines: 1,
                  style: const TextStyle(color: YsColors.mutedForeground, fontSize: 11),
                ),
            ],
          ),
        ),
        SettingsIconButton(
          icon: FLucideIcons.play,
          tooltip: 'Play recording',
          onPress: onPlay,
        ),
        const SizedBox(width: YsSpace.s1),
        SettingsIconButton(
          icon: FLucideIcons.trash2,
          tooltip: 'Delete',
          onPress: () => _confirmDelete(context, entry),
        ),
      ],
    ),
  );
}

Future<void> _confirmDelete(BuildContext context, RecordingEntry entry) async {
  final confirmed = await showYsConfirm(
    context,
    title: 'Delete recording?',
    message: entry.fileName,
    confirmLabel: 'Delete',
    destructive: true,
  );
  if (confirmed && context.mounted) {
    try {
      await context.read<RecordingProvider>().deleteRecording(entry.filePath);
    } catch (e) {
      if (!context.mounted) return;
      AppSnack.error(context, 'Could not delete recording: $e');
    }
  }
}
