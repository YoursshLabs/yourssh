import 'package:file_picker/file_picker.dart';
// Tooltip and SelectableText are Material plumbing; the rest of the screen is forui.
// Migrating the app to material_ui is a separate later step.
// ignore: deprecated_member_use
import 'package:flutter/material.dart' show SelectableText, Tooltip;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:yourssh_ui/yourssh_ui.dart';
import '../services/lan_share_service.dart';

class LanShareScreen extends StatefulWidget {
  /// [service] and [pickFile] let tests run the screen without a real HTTP
  /// server or native file dialog; the app uses the defaults.
  const LanShareScreen({super.key, this.service, this.pickFile});

  final LanShareService? service;
  final Future<FilePickerResult?> Function()? pickFile;

  @override
  State<LanShareScreen> createState() => _LanShareScreenState();
}

class _LanShareScreenState extends State<LanShareScreen> {
  late final LanShareService _service = widget.service ?? LanShareService();
  String? _shareUrl;
  String? _fileName;
  int? _fileSize;
  bool _sharing = false;

  @override
  void dispose() {
    _service.stop();
    super.dispose();
  }

  Future<void> _pickAndShare() async {
    final result =
        await (widget.pickFile?.call() ?? FilePicker.platform.pickFiles());
    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    setState(() {
      _sharing = true;
      _shareUrl = null;
    });

    final url = await _service.share(path);
    if (!mounted) return;
    setState(() {
      _sharing = false;
      _shareUrl = url;
      _fileName = result.files.single.name;
      _fileSize = result.files.single.size;
    });
  }

  Future<void> _stop() async {
    await _service.stop();
    if (!mounted) return;
    setState(() {
      _shareUrl = null;
      _fileName = null;
      _fileSize = null;
    });
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _step(String num, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: YsColors.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            num,
            style: const TextStyle(
              color: YsColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: YsSpace.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: YsColors.foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: const TextStyle(
                  color: YsColors.mutedForeground,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: YsColors.background,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(YsSpace.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_sharing)
              const Center(child: FCircularProgress())
            else if (_shareUrl == null)
              _buildIdle()
            else
              _buildSharing(),
          ],
        ),
      ),
    );
  }

  Widget _buildIdle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'LocalShare',
          style: TextStyle(
            color: YsColors.foreground,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: YsSpace.s2),
        const Text(
          'Share files on your local network over HTTP.',
          style: TextStyle(color: YsColors.mutedForeground, fontSize: 13),
        ),
        const SizedBox(height: 28),
        _step(
          '1',
          'Pick a file',
          'Any file on your Mac — image, archive, document',
        ),
        const SizedBox(height: YsSpace.s3),
        _step('2', 'Get a URL', 'A local HTTP link is generated instantly'),
        const SizedBox(height: YsSpace.s3),
        _step(
          '3',
          'Share it',
          'Anyone on the same Wi-Fi can download via browser',
        ),
        const SizedBox(height: 28),
        IntrinsicWidth(
          child: FButton(
            onPress: _pickAndShare,
            prefix: const Icon(FLucideIcons.folderOpen),
            mainAxisSize: MainAxisSize.min,
            child: const Text('Pick File to Share'),
          ),
        ),
      ],
    );
  }

  Widget _buildSharing() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(YsSpace.s4),
      decoration: BoxDecoration(
        color: YsColors.card,
        border: Border.all(color: YsColors.primary.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(YsRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                FLucideIcons.circleCheck,
                color: YsColors.ok,
                size: 16,
              ),
              const SizedBox(width: YsSpace.s2),
              Expanded(
                child: Text(
                  _fileName ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: YsColors.foreground),
                ),
              ),
            ],
          ),
          if (_fileSize != null) ...[
            const SizedBox(height: YsSpace.s1),
            Text(
              _fmtSize(_fileSize!),
              style: const TextStyle(
                color: YsColors.mutedForeground,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: YsSpace.s3),
          const Text(
            'Share URL:',
            style: TextStyle(color: YsColors.mutedForeground, fontSize: 12),
          ),
          const SizedBox(height: YsSpace.s1),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  _shareUrl!,
                  style: const TextStyle(
                    color: YsColors.accentText,
                    fontFamily: kYsMonoFontFamily,
                    fontFamilyFallback: kYsMonoFontFallback,
                    fontSize: 13,
                  ),
                ),
              ),
              Tooltip(
                message: 'Copy URL',
                excludeFromSemantics: true,
                child: FButton.icon(
                  variant: .outline,
                  size: .xs,
                  semanticsLabel: 'Copy URL',
                  onPress: () {
                    Clipboard.setData(ClipboardData(text: _shareUrl!));
                    showYsToast(
                      context,
                      'URL copied',
                      duration: const Duration(seconds: 1),
                    );
                  },
                  child: const Icon(FLucideIcons.copy),
                ),
              ),
            ],
          ),
          const SizedBox(height: YsSpace.s3),
          IntrinsicWidth(
            child: FButton(
              variant: .destructive,
              size: .sm,
              mainAxisSize: MainAxisSize.min,
              prefix: const Icon(FLucideIcons.square),
              onPress: _stop,
              child: const Text('Stop Sharing'),
            ),
          ),
        ],
      ),
    );
  }
}
