import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

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
  /// Builds the camera view and wires its detections to `onDetect`. Defaults
  /// to the real [MobileScanner]; tests inject a fake (no camera).
  final Widget Function(
    BuildContext context,
    void Function(BarcodeCapture capture) onDetect,
  )? scannerBuilder;

  const MobileQrScanScreen({super.key, this.scannerBuilder});

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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // FHeader adds the top safe area itself.
          ColoredBox(
            color: MobileColors.bg,
            child: FHeader.nested(
              prefixes: [
                Tooltip(
                  message: 'Back',
                  child: FHeaderAction.back(
                    semanticsLabel: 'Back',
                    onPress: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ],
              title: const Text('Scan transfer QR'),
            ),
          ),
          Expanded(
            child: widget.scannerBuilder?.call(context, _onDetect) ??
                MobileScanner(onDetect: _onDetect),
          ),
        ],
      ),
    );
  }
}
