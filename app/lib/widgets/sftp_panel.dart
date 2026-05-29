import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../models/sftp_entry.dart';
import '../providers/sftp_panel_provider.dart';
import '../services/sftp_transfer_service.dart';
import 'code_editor_screen.dart';

class SftpPanel extends StatefulWidget {
  final Host? host;
  final String panelId;
  final SftpPanelProvider provider;
  final VoidCallback onChangeHost;

  const SftpPanel({
    super.key,
    required this.host,
    required this.panelId,
    required this.provider,
    required this.onChangeHost,
  });

  @override
  State<SftpPanel> createState() => _SftpPanelState();
}

class _SftpPanelState extends State<SftpPanel> {
  @override
  void initState() {
    super.initState();
    if (widget.host != null) {
      _loadDirectory('/');
    }
  }

  @override
  void didUpdateWidget(SftpPanel old) {
    super.didUpdateWidget(old);
    if (old.host?.id != widget.host?.id && widget.host != null) {
      widget.provider
        ..setLoadState(SftpPanelLoadState.idle)
        ..setPath('/');
      _loadDirectory('/');
    }
  }

  Future<void> _loadDirectory(String path) async {
    final host = widget.host;
    if (host == null) return;
    widget.provider.setLoadState(SftpPanelLoadState.loading);
    widget.provider.setPath(path);
    try {
      final service = context.read<SftpTransferService>();
      final entries = await service.listDirectory(host, path);
      widget.provider.setEntries(entries);
      widget.provider.setLoadState(SftpPanelLoadState.loaded);
    } catch (e) {
      widget.provider.setLoadState(SftpPanelLoadState.error,
          error: e.toString());
    }
  }

  void _onEntryTap(SftpEntry entry) {
    if (entry.isDirectory) {
      _loadDirectory(entry.path);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              CodeEditorScreen(host: widget.host!, entry: entry),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.host == null) {
      return _buildEmptyState();
    }
    return ChangeNotifierProvider.value(
      value: widget.provider,
      child: Consumer<SftpPanelProvider>(
        builder: (context, prov, _) => Column(
          children: [
            _buildPathBar(prov),
            Expanded(child: _buildContent(prov)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.folder_outlined,
                size: 32, color: Color(0xFF444444)),
          ),
          const SizedBox(height: 16),
          const Text('Connect to host',
              style: TextStyle(
                  color: Color(0xFFD4D4D4),
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text(
            'Start by connecting to a saved host\nto manage your files with SFTP.',
            style: TextStyle(color: Color(0xFF555555), fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: widget.onChangeHost,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: const Text('Select host',
                  style: TextStyle(
                      color: Color(0xFFD4D4D4),
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPathBar(SftpPanelProvider prov) {
    return Container(
      height: 36,
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward,
                size: 14, color: Color(0xFF888888)),
            onPressed: () {
              prov.navigateUp();
              _loadDirectory(prov.currentPath);
            },
            tooltip: 'Up',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          GestureDetector(
            onTap: widget.onChangeHost,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.dns, size: 11, color: Color(0xFF22C55E)),
                  const SizedBox(width: 4),
                  Text(
                    '${widget.host!.username}@${widget.host!.host}',
                    style: const TextStyle(
                        color: Color(0xFF22C55E),
                        fontSize: 11,
                        fontFamily: 'monospace'),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.unfold_more,
                      size: 11, color: Color(0xFF555555)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              prov.currentPath,
              style: const TextStyle(
                  color: Color(0xFF888888),
                  fontFamily: 'monospace',
                  fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh,
                size: 14, color: Color(0xFF888888)),
            onPressed: () => _loadDirectory(prov.currentPath),
            tooltip: 'Refresh',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(SftpPanelProvider prov) {
    if (prov.loadState == SftpPanelLoadState.loading) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF22C55E)));
    }
    if (prov.loadState == SftpPanelLoadState.error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 32),
            const SizedBox(height: 8),
            Text(prov.errorMessage ?? 'Error',
                style: const TextStyle(color: Colors.red, fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }
    if (prov.entries.isEmpty) {
      return const Center(
        child: Text('Empty directory',
            style: TextStyle(color: Color(0xFF555555))),
      );
    }
    return ListView.builder(
      itemCount: prov.entries.length,
      itemBuilder: (_, i) => _buildEntryTile(prov.entries[i], prov),
    );
  }

  Widget _buildEntryTile(SftpEntry entry, SftpPanelProvider prov) {
    final isSelected = prov.selectedEntries.contains(entry);
    return Draggable<SftpEntry>(
      data: entry,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF22C55E).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(entry.name,
              style: const TextStyle(
                  color: Color(0xFF22C55E), fontSize: 13)),
        ),
      ),
      child: InkWell(
        onTap: () => _onEntryTap(entry),
        onSecondaryTap: () => prov.toggleSelection(entry),
        child: Container(
          color: isSelected
              ? const Color(0xFF22C55E).withValues(alpha: 0.1)
              : Colors.transparent,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Icon(
                entry.isDirectory
                    ? Icons.folder
                    : _fileIcon(entry.extension),
                size: 16,
                color: entry.isDirectory
                    ? const Color(0xFFFBBF24)
                    : const Color(0xFF60A5FA),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(entry.name,
                    style: const TextStyle(
                        color: Color(0xFFD4D4D4), fontSize: 13),
                    overflow: TextOverflow.ellipsis),
              ),
              Text(entry.formattedSize,
                  style: const TextStyle(
                      color: Color(0xFF555555), fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  IconData _fileIcon(String ext) {
    return switch (ext) {
      'dart' ||
      'py' ||
      'js' ||
      'ts' ||
      'go' ||
      'rs' ||
      'c' ||
      'cpp' =>
        Icons.code,
      'json' || 'yaml' || 'yml' || 'toml' || 'xml' => Icons.data_object,
      'md' || 'txt' || 'log' => Icons.article,
      'sh' || 'bash' || 'zsh' => Icons.terminal,
      _ => Icons.insert_drive_file,
    };
  }
}
