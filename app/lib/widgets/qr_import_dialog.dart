import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/host_provider.dart';
import '../services/p2p_sync_encryption.dart';
import '../services/p2p_sync_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';

class QrImportDialog extends StatefulWidget {
  const QrImportDialog({super.key});

  @override
  State<QrImportDialog> createState() => _QrImportDialogState();
}

class _QrImportDialogState extends State<QrImportDialog> {
  final _controller = TextEditingController();
  final _p2pService = P2PSyncService();
  bool _processing = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _p2pService.stop();
    super.dispose();
  }

  Future<void> _loadFromFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.single.path == null) return;
    final content = await File(result.files.single.path!).readAsString();
    if (mounted) {
      _controller.text = content.trim();
      setState(() => _error = null);
    }
  }

  Future<void> _import() async {
    if (_processing) return;
    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final json = jsonDecode(_controller.text.trim()) as Map<String, dynamic>;
      final url = json['u'] as String?;
      final k = json['k'] as String?;
      if (url == null || k == null) throw const FormatException('missing fields');
      final key = base64.decode(k);

      final encrypted = await _p2pService.fetchPayload(url);
      final decrypted = await P2PSyncEncryption.decrypt(encrypted, key);
      final payload = SyncService.parsePayload(decrypted);

      if (payload.hosts.isEmpty) throw Exception('No hosts found in transfer');

      if (!mounted) return;
      await context.read<HostProvider>().replaceAll(payload.hosts, payload.passwords);

      if (mounted) {
        setState(() => _processing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Imported ${payload.hosts.length} host${payload.hosts.length == 1 ? '' : 's'}. '
            'All previous hosts replaced.',
          ),
        ));
        Navigator.of(context).pop();
      }
    } on FormatException {
      if (mounted) setState(() { _processing = false; _error = 'Invalid transfer code.'; });
    } on SocketException {
      if (mounted) setState(() { _processing = false; _error = 'Cannot reach device. Make sure both are on the same network.'; });
    } on TimeoutException {
      if (mounted) setState(() { _processing = false; _error = 'Cannot reach device. Make sure both are on the same network.'; });
    } catch (e) {
      if (mounted) setState(() { _processing = false; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.sidebar,
      title: const Text('Import via Transfer Code'),
      content: SizedBox(
        width: 360,
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paste the transfer code from the exporting device.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: '{"u":"http://...","k":"..."}',
                  hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                  filled: true,
                  fillColor: AppColors.card,
                  border: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.folder_open, size: 16),
                label: const Text('Load from file'),
                onPressed: _processing ? null : _loadFromFile,
              ),
              if (_processing) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => FilledButton(
            onPressed: (_processing || _controller.text.trim().isEmpty) ? null : _import,
            child: const Text('Import'),
          ),
        ),
      ],
    );
  }
}
