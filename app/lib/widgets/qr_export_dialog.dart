import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/p2p_sync_encryption.dart';
import '../services/p2p_sync_service.dart';
import '../theme/app_theme.dart';

class QrExportDialog extends StatefulWidget {
  final Future<String> Function() getPayload;

  const QrExportDialog({super.key, required this.getPayload});

  @override
  State<QrExportDialog> createState() => _QrExportDialogState();
}

class _QrExportDialogState extends State<QrExportDialog> {
  final _service = P2PSyncService();
  List<NetworkInterfaceInfo> _interfaces = [];
  NetworkInterfaceInfo? _selectedInterface;
  String? _qrData;
  String _status = 'Initializing...';
  int _secondsLeft = 120;
  Timer? _countdown;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final ifaces = await _service.getLocalInterfaces();
      if (!mounted) return;
      if (ifaces.isEmpty) {
        setState(() => _status = 'No network interface found.');
        return;
      }
      setState(() {
        _interfaces = ifaces;
        _selectedInterface = ifaces.first;
      });
      await _startServer();
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: $e');
    }
  }

  Future<void> _startServer() async {
    if (_selectedInterface == null) return;
    setState(() {
      _qrData = null;
      _status = 'Preparing data...';
    });
    _countdown?.cancel();

    try {
      final payload = await widget.getPayload();
      final key = P2PSyncEncryption.generateKey();
      final encrypted = await P2PSyncEncryption.encrypt(payload, key);
      final url = await _service.startServer(
        encryptedPayload: encrypted,
        hostAddress: _selectedInterface!.address,
      );
      final qrJson = jsonEncode({'u': url, 'k': base64.encode(key)});

      _secondsLeft = 120;
      _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (_secondsLeft <= 0) {
          t.cancel();
          _service.stop();
          if (mounted) setState(() => _status = 'Session expired.');
          return;
        }
        setState(() => _secondsLeft--);
      });

      if (mounted) {
        setState(() {
          _qrData = qrJson;
          _status = 'Waiting for device to scan...';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: $e');
    }
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _service.stop();
    super.dispose();
  }

  String get _countdownText {
    final m = _secondsLeft ~/ 60;
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.sidebar,
      title: const Text('Export via QR'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_interfaces.length > 1) ...[
              DropdownButtonFormField<NetworkInterfaceInfo>(
                initialValue: _selectedInterface,
                decoration: const InputDecoration(labelText: 'Network interface'),
                items: _interfaces
                    .map((i) => DropdownMenuItem(value: i, child: Text(i.toString())))
                    .toList(),
                onChanged: (v) async {
                  if (v == null) return;
                  setState(() => _selectedInterface = v);
                  _service.stop();
                  await _startServer();
                },
              ),
              const SizedBox(height: 16),
            ],
            if (_qrData != null) ...[
              QrImageView(
                data: _qrData!,
                size: 240,
                backgroundColor: Colors.white,
              ),
              const SizedBox(height: 8),
              Text(
                _countdownText,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
            ] else
              const SizedBox(
                height: 240,
                child: Center(child: CircularProgressIndicator()),
              ),
            const SizedBox(height: 8),
            Text(
              _status,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        if (_qrData != null)
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy transfer code'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _qrData!));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Transfer code copied'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        TextButton(
          onPressed: () {
            _countdown?.cancel();
            _service.stop();
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
