import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../models/local_entry.dart';
import '../models/sftp_entry.dart';
import '../models/sftp_transfer_item.dart';
import '../providers/host_provider.dart';
import '../providers/local_file_panel_provider.dart';
import '../providers/sftp_panel_provider.dart';
import '../providers/sftp_transfer_provider.dart';
import '../services/sftp_file_ops_service.dart';
import '../services/sftp_transfer_service.dart';
import '../services/ssh_service.dart';
import 'local_file_panel.dart';
import 'sftp_panel.dart';
import 'sftp_transfer_dialog.dart';

class DualPanelSftpScreen extends StatefulWidget {
  final ValueNotifier<bool> connectionNotifier;

  const DualPanelSftpScreen({super.key, required this.connectionNotifier});

  @override
  State<DualPanelSftpScreen> createState() => _DualPanelSftpScreenState();
}

class _DualPanelSftpScreenState extends State<DualPanelSftpScreen> {
  Host? _hostA;
  Host? _hostB;
  late LocalFilePanelProvider _localProvider;
  late SftpPanelProvider _providerA;
  late SftpPanelProvider _providerB;
  late SftpTransferProvider _transferProvider;

  @override
  void initState() {
    super.initState();
    _localProvider = LocalFilePanelProvider();
    _providerA = SftpPanelProvider();
    _providerB = SftpPanelProvider();
    _transferProvider = SftpTransferProvider();
    widget.connectionNotifier.value = false;
  }

  @override
  void dispose() {
    widget.connectionNotifier.value = false;
    _localProvider.dispose();
    _providerA.dispose();
    _providerB.dispose();
    _transferProvider.dispose();
    super.dispose();
  }

  Future<Host?> _showHostPicker(Host? current) {
    final hosts = context.read<HostProvider>().allHosts;
    if (hosts.isEmpty) return Future.value(null);
    return showDialog<Host>(
      context: context,
      builder: (ctx) => _HostPickerDialog(hosts: hosts, current: current),
    );
  }

  Future<void> _pickHostA() async {
    final h = await _showHostPicker(_hostA);
    if (h != null && h.id != _hostA?.id) setState(() { _hostA = h; widget.connectionNotifier.value = true; });
  }

  Future<void> _pickHostB() async {
    final h = await _showHostPicker(_hostB);
    if (h != null && h.id != _hostB?.id) setState(() => _hostB = h);
  }

  void _showTransferDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChangeNotifierProvider.value(
        value: _transferProvider,
        child: const SftpTransferDialog(),
      ),
    );
  }

  Future<void> _reloadA() async {
    if (!mounted || _hostA == null) return;
    _providerA.setLoadState(SftpPanelLoadState.loading);
    try {
      final entries = await context.read<SftpTransferService>().listDirectory(_hostA!, _providerA.currentPath);
      _providerA..setEntries(entries)..setLoadState(SftpPanelLoadState.loaded);
    } catch (e) { _providerA.setLoadState(SftpPanelLoadState.error, error: e.toString()); }
  }

  Future<void> _reloadB() async {
    if (!mounted || _hostB == null) return;
    _providerB.setLoadState(SftpPanelLoadState.loading);
    try {
      final entries = await context.read<SftpTransferService>().listDirectory(_hostB!, _providerB.currentPath);
      _providerB..setEntries(entries)..setLoadState(SftpPanelLoadState.loaded);
    } catch (e) { _providerB.setLoadState(SftpPanelLoadState.error, error: e.toString()); }
  }

  // ── Local → RemoteA ───────────────────────────────────

  Future<void> _upload() async {
    final host = _hostA;
    if (host == null) return;
    final selected = _localProvider.selectedEntries.toList();
    if (selected.isEmpty) return;
    final service = context.read<SftpTransferService>();
    final remoteDir = _providerA.currentPath;

    final items = [
      for (final e in selected)
        SftpTransferItem(fileName: e.name, direction: TransferDirection.upload)..totalBytes = e.size,
    ];
    _transferProvider.startBatch(items);
    _showTransferDialog();

    try {
      for (int i = 0; i < selected.length; i++) {
        if (_transferProvider.isCancelled) break;
        final item = items[i];
        final entry = selected[i];
        _transferProvider.updateItem(item.id, status: TransferStatus.inProgress);
        if (entry.isDirectory) {
          await service.uploadDirectory(
            localDir: entry.path, remoteHost: host,
            remoteDir: remoteDir == '/' ? '/${entry.name}' : '$remoteDir/${entry.name}',
            onProgress: (_, bytes, total) => _transferProvider.updateItem(item.id, bytesTransferred: bytes),
            onFileSkipped: (_) {},
            isCancelled: () => _transferProvider.isCancelled,
          );
        } else {
          await service.copyLocalToRemote(localPath: entry.path, remoteHost: host, remoteDir: remoteDir);
          _transferProvider.updateItem(item.id, bytesTransferred: entry.size);
        }
        _transferProvider.updateItem(item.id, status: TransferStatus.done);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Upload failed: $e'), backgroundColor: const Color(0xFF2A1A1A)));
      }
    } finally { await _reloadA(); }
  }

  // ── RemoteA → Local ───────────────────────────────────

  Future<void> _download() async {
    final host = _hostA;
    if (host == null) return;
    final selected = _providerA.selectedEntries.toList();
    if (selected.isEmpty) return;
    final service = context.read<SftpTransferService>();
    final localDir = _localProvider.currentPath;

    final items = [
      for (final e in selected)
        SftpTransferItem(fileName: e.name, direction: TransferDirection.download)..totalBytes = e.size,
    ];
    _transferProvider.startBatch(items);
    _showTransferDialog();

    try {
      for (int i = 0; i < selected.length; i++) {
        if (_transferProvider.isCancelled) break;
        final item = items[i];
        final entry = selected[i];
        _transferProvider.updateItem(item.id, status: TransferStatus.inProgress);
        if (entry.isDirectory) {
          await service.downloadDirectory(
            remoteHost: host, remoteDir: entry, localDir: localDir,
            onProgress: (_, bytes, total) => _transferProvider.updateItem(item.id, bytesTransferred: bytes),
            onFileSkipped: (_) {},
            isCancelled: () => _transferProvider.isCancelled,
          );
        } else {
          await service.copyRemoteToLocal(remoteHost: host, remoteEntry: entry, localDir: localDir);
          _transferProvider.updateItem(item.id, bytesTransferred: entry.size);
        }
        _transferProvider.updateItem(item.id, status: TransferStatus.done);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download failed: $e'), backgroundColor: const Color(0xFF2A1A1A)));
      }
    } finally { await _localProvider.reload(); }
  }

  // ── RemoteA → RemoteB ─────────────────────────────────

  Future<void> _copyAtoB() async {
    final hostA = _hostA; final hostB = _hostB;
    if (hostA == null || hostB == null) return;
    final selected = _providerA.selectedEntries.where((e) => !e.isDirectory).toList();
    if (selected.isEmpty) return;
    final service = context.read<SftpTransferService>();
    final destDir = _providerB.currentPath;

    final items = [for (final e in selected) SftpTransferItem(fileName: e.name, direction: TransferDirection.upload)..totalBytes = e.size];
    _transferProvider.startBatch(items);
    _showTransferDialog();

    try {
      for (int i = 0; i < selected.length; i++) {
        if (_transferProvider.isCancelled) break;
        final item = items[i]; final entry = selected[i];
        _transferProvider.updateItem(item.id, status: TransferStatus.inProgress);
        final tmp = await service.downloadToTemp(hostA, entry);
        if (tmp != null) {
          await service.copyLocalToRemote(localPath: tmp, remoteHost: hostB, remoteDir: destDir);
          await File(tmp).delete();
        }
        _transferProvider.updateItem(item.id, bytesTransferred: entry.size, status: TransferStatus.done);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Copy failed: $e'), backgroundColor: const Color(0xFF2A1A1A)));
      }
    } finally { await _reloadB(); }
  }

  // ── RemoteB → RemoteA ─────────────────────────────────

  Future<void> _copyBtoA() async {
    final hostA = _hostA; final hostB = _hostB;
    if (hostA == null || hostB == null) return;
    final selected = _providerB.selectedEntries.where((e) => !e.isDirectory).toList();
    if (selected.isEmpty) return;
    final service = context.read<SftpTransferService>();
    final destDir = _providerA.currentPath;

    final items = [for (final e in selected) SftpTransferItem(fileName: e.name, direction: TransferDirection.upload)..totalBytes = e.size];
    _transferProvider.startBatch(items);
    _showTransferDialog();

    try {
      for (int i = 0; i < selected.length; i++) {
        if (_transferProvider.isCancelled) break;
        final item = items[i]; final entry = selected[i];
        _transferProvider.updateItem(item.id, status: TransferStatus.inProgress);
        final tmp = await service.downloadToTemp(hostB, entry);
        if (tmp != null) {
          await service.copyLocalToRemote(localPath: tmp, remoteHost: hostA, remoteDir: destDir);
          await File(tmp).delete();
        }
        _transferProvider.updateItem(item.id, bytesTransferred: entry.size, status: TransferStatus.done);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Copy failed: $e'), backgroundColor: const Color(0xFF2A1A1A)));
      }
    } finally { await _reloadA(); }
  }

  // ── Drag & Drop ───────────────────────────────────────

  Future<void> _onLocalDroppedOnRemote(LocalEntry entry) async {
    if (_hostA == null || entry.isDirectory) return;
    _localProvider.selectOnly(entry);
    await _upload();
  }

  Future<void> _onRemoteDroppedOnLocal(SftpEntry entry) async {
    if (_hostA == null || entry.isDirectory) return;
    _providerA.clearSelection();
    _providerA.toggleSelection(entry);
    await _download();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (ctx) => SftpTransferService(ctx.read<SshService>())),
        Provider(create: (ctx) => SftpFileOpsService(ctx.read<SshService>())),
        ChangeNotifierProvider.value(value: _transferProvider),
      ],
      child: ListenableBuilder(
        listenable: Listenable.merge([_localProvider, _providerA, _providerB]),
        builder: (context, _) => Column(
          children: [
            Consumer<SftpTransferProvider>(
              builder: (_, tp, _) => tp.isTransferring
                  ? LinearProgressIndicator(
                      value: tp.overallProgress > 0 ? tp.overallProgress : null,
                      color: const Color(0xFF22C55E),
                      backgroundColor: const Color(0xFF1A1A1A),
                      minHeight: 2)
                  : const SizedBox.shrink(),
            ),
            Expanded(
              child: Row(
                children: [
                  // Local
                  Expanded(
                    child: DragTarget<SftpEntry>(
                      onAcceptWithDetails: (d) => _onRemoteDroppedOnLocal(d.data),
                      builder: (_, candidates, _) => Container(
                        decoration: BoxDecoration(
                          border: candidates.isNotEmpty
                              ? Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.4), width: 2)
                              : null,
                        ),
                        child: LocalFilePanel(provider: _localProvider),
                      ),
                    ),
                  ),
                  // Bar: Local ↔ RemoteA
                  _TransferBar(
                    canLeft: _hostA != null && _providerA.selectedEntries.isNotEmpty,
                    canRight: _hostA != null && _localProvider.selectedEntries.isNotEmpty,
                    onLeft: _download,
                    onRight: _upload,
                  ),
                  // RemoteA
                  Expanded(
                    child: DragTarget<LocalEntry>(
                      onAcceptWithDetails: (d) => _onLocalDroppedOnRemote(d.data),
                      builder: (_, candidates, _) => Container(
                        decoration: BoxDecoration(
                          border: candidates.isNotEmpty
                              ? Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.4), width: 2)
                              : null,
                        ),
                        child: SftpPanel(
                          key: ValueKey('ra_${_hostA?.id}'),
                          host: _hostA, panelId: 'remote_a',
                          provider: _providerA, onChangeHost: _pickHostA,
                        ),
                      ),
                    ),
                  ),
                  // Bar: RemoteA ↔ RemoteB
                  _TransferBar(
                    canLeft: _hostA != null && _hostB != null && _providerB.selectedEntries.any((e) => !e.isDirectory),
                    canRight: _hostA != null && _hostB != null && _providerA.selectedEntries.any((e) => !e.isDirectory),
                    onLeft: _copyBtoA,
                    onRight: _copyAtoB,
                  ),
                  // RemoteB
                  Expanded(
                    child: SftpPanel(
                      key: ValueKey('rb_${_hostB?.id}'),
                      host: _hostB, panelId: 'remote_b',
                      provider: _providerB, onChangeHost: _pickHostB,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferBar extends StatelessWidget {
  final bool canLeft;
  final bool canRight;
  final VoidCallback onLeft;
  final VoidCallback onRight;

  const _TransferBar({required this.canLeft, required this.canRight, required this.onLeft, required this.onRight});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      color: const Color(0xFF111111),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Btn(icon: Icons.arrow_forward, tooltip: 'Copy →', enabled: canRight, onTap: onRight),
          const SizedBox(height: 8),
          _Btn(icon: Icons.arrow_back, tooltip: 'Copy ←', enabled: canLeft, onTap: onLeft),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  const _Btn({required this.icon, required this.tooltip, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 26, height: 26,
          decoration: BoxDecoration(
            color: enabled ? const Color(0xFF22C55E).withValues(alpha: 0.12) : const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: enabled ? const Color(0xFF22C55E).withValues(alpha: 0.3) : const Color(0xFF252525)),
          ),
          child: Icon(icon, size: 14, color: enabled ? const Color(0xFF22C55E) : const Color(0xFF333333)),
        ),
      ),
    );
  }
}

class _HostPickerDialog extends StatelessWidget {
  final List<Host> hosts;
  final Host? current;

  const _HostPickerDialog({required this.hosts, required this.current});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A)))),
              child: Row(children: [
                const Icon(Icons.dns_outlined, size: 15, color: Color(0xFF888888)),
                const SizedBox(width: 8),
                const Text('Select Remote Host',
                    style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                GestureDetector(onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, size: 14, color: Color(0xFF555555))),
              ]),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: hosts.length,
                itemBuilder: (_, i) {
                  final h = hosts[i];
                  final active = h.id == current?.id;
                  return InkWell(
                    onTap: () => Navigator.pop(context, h),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      color: active ? const Color(0xFF22C55E).withValues(alpha: 0.08) : Colors.transparent,
                      child: Row(children: [
                        Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.dns, size: 14, color: Color(0xFF22C55E)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(h.label, style: TextStyle(
                              color: active ? const Color(0xFF22C55E) : const Color(0xFFD4D4D4),
                              fontSize: 13, fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
                            Text('${h.username}@${h.host}:${h.port}',
                                style: const TextStyle(color: Color(0xFF555555), fontSize: 11, fontFamily: 'monospace')),
                          ],
                        )),
                        if (active) const Icon(Icons.check, size: 14, color: Color(0xFF22C55E)),
                      ]),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
