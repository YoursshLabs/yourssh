import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../theme/terminal_themes.dart';
import '../providers/settings_provider.dart';

class RecordingPlayerWidget extends StatefulWidget {
  final String filePath;
  const RecordingPlayerWidget({super.key, required this.filePath});

  @override
  State<RecordingPlayerWidget> createState() => _RecordingPlayerWidgetState();
}

class _RecordingPlayerWidgetState extends State<RecordingPlayerWidget> {
  late final Terminal _terminal;
  List<_CastEvent> _events = [];
  int _currentIndex = 0;
  bool _playing = false;
  bool _loading = true;
  String? _error;
  double _speed = 1.0;
  Timer? _timer;

  static const _speeds = [0.5, 1.0, 2.0, 5.0];

  @override
  void initState() {
    super.initState();
    _terminal = Terminal();
    _loadFile();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadFile() async {
    try {
      final lines = await File(widget.filePath).readAsLines();
      if (!mounted) return;
      if (lines.isEmpty) throw const FormatException('Empty file');

      // Parse header for metadata (width/height); terminal is sized by the widget.
      final header = jsonDecode(lines.first) as Map<String, dynamic>;
      final int cols = (header['width'] as num?)?.toInt() ?? 80;
      final int rows = (header['height'] as num?)?.toInt() ?? 24;
      _terminal.resize(cols, rows);

      final events = <_CastEvent>[];
      for (final line in lines.skip(1)) {
        if (line.trim().isEmpty) continue;
        try {
          final arr = jsonDecode(line) as List;
          if (arr.length >= 3 && arr[1] == 'o') {
            events.add(_CastEvent((arr[0] as num).toDouble(), arr[2] as String));
          }
        } catch (_) {}
      }
      if (mounted) setState(() { _events = events; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _play() {
    if (_events.isEmpty || _playing) return;
    if (_currentIndex >= _events.length) {
      _terminal.buffer.clear();
      _currentIndex = 0;
    }
    setState(() => _playing = true);
    _scheduleNext();
  }

  void _pause() {
    _timer?.cancel();
    if (mounted) setState(() => _playing = false);
  }

  void _scheduleNext() {
    _timer?.cancel();
    if (!mounted) return;
    if (_currentIndex >= _events.length) {
      setState(() => _playing = false);
      return;
    }
    final event = _events[_currentIndex];
    final prevElapsed = _currentIndex > 0 ? _events[_currentIndex - 1].elapsed : 0.0;
    final gap = (event.elapsed - prevElapsed).clamp(0.0, 5.0);
    final delayMs = (gap / _speed * 1000).round();

    _timer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      _terminal.write(event.data);
      _currentIndex++;
      if (mounted) setState(() {});
      _scheduleNext();
    });
  }

  Duration get _totalDuration {
    if (_events.isEmpty) return Duration.zero;
    return Duration(milliseconds: (_events.last.elapsed * 1000).round());
  }

  Duration get _currentPosition {
    if (_events.isEmpty || _currentIndex == 0) return Duration.zero;
    final idx = (_currentIndex - 1).clamp(0, _events.length - 1);
    return Duration(milliseconds: (_events[idx].elapsed * 1000).round());
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
      );
    }

    final settings = context.watch<SettingsProvider>();
    final theme = terminalThemeByName(settings.terminalTheme);
    final progress = _events.isEmpty ? 0.0 : _currentIndex / _events.length;
    final keywordRules = settings.xtermKeywordRules;

    return Column(
      children: [
        Expanded(
          child: TerminalView(
            _terminal,
            theme: theme,
            textStyle: TerminalStyle(fontSize: settings.fontSize, fontFamily: settings.terminalFont),
            padding: EdgeInsets.zero,
            autofocus: false,
            readOnly: true,
            keywordRules: keywordRules,
          ),
        ),
        Container(
          color: AppColors.sidebar,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    _formatDuration(_currentPosition),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11, fontFamily: 'monospace'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: AppColors.border,
                      color: AppColors.accent,
                      minHeight: 3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDuration(_totalDuration),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11, fontFamily: 'monospace'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(
                      _playing ? Icons.pause : Icons.play_arrow,
                      color: AppColors.textPrimary,
                    ),
                    onPressed: _playing ? _pause : _play,
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<double>(
                    value: _speed,
                    dropdownColor: AppColors.sidebar,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    items: _speeds
                        .map((s) => DropdownMenuItem(value: s, child: Text('${s}x')))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      final wasPlaying = _playing;
                      _pause();
                      setState(() => _speed = v);
                      if (wasPlaying) _play();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CastEvent {
  final double elapsed;
  final String data;
  const _CastEvent(this.elapsed, this.data);
}
