import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../providers/host_provider.dart';
import '../services/p2p_sync_encryption.dart';
import '../services/p2p_sync_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';

class QrImportScreen extends StatefulWidget {
  const QrImportScreen({super.key});

  @override
  State<QrImportScreen> createState() => _QrImportScreenState();
}

class _QrImportScreenState extends State<QrImportScreen> {
  final _p2pService = P2PSyncService();
  bool _processing = false;
  String? _error;
  bool _done = false;

  Future<void> _onQrDetected(String rawValue) async {
    if (_processing || _done) return;
    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final json = jsonDecode(rawValue) as Map<String, dynamic>;
      final url = json['u'] as String;
      final key = base64.decode(json['k'] as String);

      final encrypted = await _p2pService.fetchPayload(url);
      final decrypted = await P2PSyncEncryption.decrypt(encrypted, key);
      final payload = SyncService.parsePayload(decrypted);

      if (payload.hosts.isEmpty) {
        throw Exception('No hosts found in transfer');
      }

      if (!mounted) return;
      await context.read<HostProvider>().replaceAll(
            payload.hosts,
            payload.passwords,
          );

      setState(() => _done = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported ${payload.hosts.length} host${payload.hosts.length == 1 ? '' : 's'}. All previous hosts replaced.',
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } on FormatException {
      if (mounted) setState(() { _processing = false; _error = 'Invalid QR code.'; });
    } catch (e) {
      final isNetworkError = e.toString().contains('HTTP') ||
          e.toString().contains('Connection') ||
          e.toString().contains('refused') ||
          e.toString().contains('timeout');
      final msg = isNetworkError
          ? 'Cannot reach device. Make sure both are on the same network.'
          : e.toString().replaceFirst('Exception: ', '');
      if (mounted) setState(() { _processing = false; _error = msg; });
    }
  }

  @override
  void dispose() {
    _p2pService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Scan QR to Import'),
        backgroundColor: AppColors.sidebar,
      ),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              final barcode = capture.barcodes.firstOrNull;
              if (barcode?.rawValue != null) {
                _onQrDetected(barcode!.rawValue!);
              }
            },
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (_processing)
            Container(
              color: Colors.black45,
              child: const Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            Positioned(
              bottom: 40,
              left: 24,
              right: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => setState(() => _error = null),
                      child: const Text('Retry', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
