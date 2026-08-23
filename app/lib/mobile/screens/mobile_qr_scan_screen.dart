import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../providers/host_provider.dart';
import '../../services/p2p_sync_encryption.dart';
import '../../services/p2p_sync_service.dart';
import '../../services/sync_service.dart';
import '../theme/mobile_theme.dart';
import '../sync/transfer_code.dart';

/// Full-screen camera QR scanner for P2P host import. On the first valid code
/// it fetches + decrypts the payload from the exporting device and replaces
/// the local host list, then pops a result message (shown as a SnackBar by the
/// caller).
class MobileQrScanScreen extends StatefulWidget {
  const MobileQrScanScreen({super.key});

  @override
  State<MobileQrScanScreen> createState() => _MobileQrScanScreenState();
}

class _MobileQrScanScreenState extends State<MobileQrScanScreen> {
  final _p2p = P2PSyncService();
  bool _handled = false;

  @override
  void dispose() {
    _p2p.stop();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (raw == null) return;
    _handled = true;
    try {
      final code = parseTransferCode(raw);
      final encrypted = await _p2p.fetchPayload(code.url);
      final decrypted = await P2PSyncEncryption.decrypt(encrypted, code.key);
      final payload = SyncService.parsePayload(decrypted);
      if (payload.hosts.isEmpty) {
        throw const FormatException('No hosts in transfer');
      }
      if (!mounted) return;
      await context
          .read<HostProvider>()
          .replaceAll(payload.hosts, payload.passwords);
      if (mounted) {
        Navigator.of(context).pop('Imported ${payload.hosts.length} hosts');
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(
            'Import failed: ${e.toString().replaceFirst('FormatException: ', '')}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: MobileColors.bg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          color: MobileColors.accent,
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Back',
        ),
        title: Text('Scan transfer QR', style: mobileHeading()),
      ),
      body: MobileScanner(onDetect: _onDetect),
    );
  }
}
