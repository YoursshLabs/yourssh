import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/lan_share_service.dart';
import '../theme.dart';

class LanShareScreen extends StatefulWidget {
  const LanShareScreen({super.key});

  @override
  State<LanShareScreen> createState() => _LanShareScreenState();
}

class _LanShareScreenState extends State<LanShareScreen> {
  final _service = LanShareService();
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
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;

    final path = result.files.single.path!;
    setState(() {
      _sharing = true;
      _shareUrl = null;
    });

    final url = await _service.share(path);
    setState(() {
      _sharing = false;
      _shareUrl = url;
      _fileName = result.files.single.name;
      _fileSize = result.files.single.size;
    });
  }

  Future<void> _stop() async {
    await _service.stop();
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
            color: DevOpsColors.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(num,
              style: const TextStyle(
                  color: DevOpsColors.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: DevOpsColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(desc,
                  style: const TextStyle(
                      color: DevOpsColors.textTertiary, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_sharing) ...[
            const Center(
                child: CircularProgressIndicator(color: DevOpsColors.accent)),
          ] else if (_shareUrl == null) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('LocalShare',
                    style: TextStyle(
                        color: DevOpsColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text('Share files on your local network over HTTP.',
                    style:
                        TextStyle(color: DevOpsColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 28),
                _step('1', 'Pick a file',
                    'Any file on your Mac — image, archive, document'),
                const SizedBox(height: 12),
                _step('2', 'Get a URL',
                    'A local HTTP link is generated instantly'),
                const SizedBox(height: 12),
                _step('3', 'Share it',
                    'Anyone on the same Wi-Fi can download via browser'),
                const SizedBox(height: 28),
                ElevatedButton.icon(
                  onPressed: _pickAndShare,
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: const Text('Pick File to Share'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DevOpsColors.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: DevOpsColors.card,
                border: Border.all(
                    color: DevOpsColors.accent.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: DevOpsColors.accent, size: 16),
                      const SizedBox(width: 8),
                      Text(_fileName ?? '',
                          style: const TextStyle(color: DevOpsColors.textPrimary)),
                    ],
                  ),
                  if (_fileSize != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _fmtSize(_fileSize!),
                      style: const TextStyle(
                          color: DevOpsColors.textTertiary, fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text('Share URL:',
                      style: TextStyle(
                          color: DevOpsColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          _shareUrl!,
                          style: const TextStyle(
                            color: DevOpsColors.blue,
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy,
                            size: 16, color: DevOpsColors.textSecondary),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _shareUrl!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('URL copied'),
                                duration: Duration(seconds: 1)),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _stop,
                    icon: const Icon(Icons.stop,
                        size: 16, color: DevOpsColors.red),
                    label: const Text('Stop Sharing',
                        style: TextStyle(color: DevOpsColors.red)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
