// app/lib/widgets/sftp_panel.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/sftp_entry.dart';
import '../models/ssh_session.dart';
import '../providers/sftp_panel_provider.dart';
import '../services/sftp_transfer_service.dart';
import 'code_editor_screen.dart';

class SftpPanel extends StatefulWidget {
  final SshSession session;
  final String panelId; // 'left' or 'right'

  const SftpPanel({super.key, required this.session, required this.panelId});

  @override
  State<SftpPanel> createState() => _SftpPanelState();
}

class _SftpPanelState extends State<SftpPanel> {
  late SftpPanelProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = SftpPanelProvider();
    _loadDirectory('/');
  }

  Future<void> _loadDirectory(String path) async {
    _provider.setLoadState(SftpPanelLoadState.loading);
    _provider.setPath(path);
    try {
      final service = context.read<SftpTransferService>();
      final entries = await service.listDirectory(widget.session.host, path);
      _provider.setEntries(entries);
      _provider.setLoadState(SftpPanelLoadState.loaded);
    } catch (e) {
      _provider.setLoadState(SftpPanelLoadState.error, error: e.toString());
    }
  }

  void _onEntryTap(SftpEntry entry) {
    if (entry.isDirectory) {
      _loadDirectory(entry.path);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CodeEditorScreen(
            session: widget.session,
            entry: entry,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: Consumer<SftpPanelProvider>(
        builder: (context, provider, _) => Column(
          children: [
            _buildPathBar(provider),
            Expanded(child: _buildContent(provider)),
          ],
        ),
      ),
    );
  }

  Widget _buildPathBar(SftpPanelProvider provider) {
    return Container(
      height: 36,
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 14, color: Color(0xFF888888)),
            onPressed: () {
              provider.navigateUp();
              _loadDirectory(provider.currentPath);
            },
            tooltip: 'Up',
          ),
          Expanded(
            child: Text(
              provider.currentPath,
              style: const TextStyle(
                color: Color(0xFFD4D4D4),
                fontFamily: 'monospace',
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 14, color: Color(0xFF888888)),
            onPressed: () => _loadDirectory(provider.currentPath),
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _buildContent(SftpPanelProvider provider) {
    if (provider.loadState == SftpPanelLoadState.loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF22C55E)));
    }
    if (provider.loadState == SftpPanelLoadState.error) {
      return Center(
        child: Text(
          provider.errorMessage ?? 'Error',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
    if (provider.entries.isEmpty) {
      return const Center(
        child: Text('Empty directory', style: TextStyle(color: Color(0xFF555555))),
      );
    }
    return ListView.builder(
      itemCount: provider.entries.length,
      itemBuilder: (_, i) => _buildEntryTile(provider.entries[i], provider),
    );
  }

  Widget _buildEntryTile(SftpEntry entry, SftpPanelProvider provider) {
    final isSelected = provider.selectedEntries.contains(entry);
    return InkWell(
      onTap: () => _onEntryTap(entry),
      onSecondaryTap: () => provider.toggleSelection(entry),
      child: Container(
        color: isSelected ? const Color(0xFF22C55E).withValues(alpha: 0.1) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(
              entry.isDirectory ? Icons.folder : _fileIcon(entry.extension),
              size: 16,
              color: entry.isDirectory ? const Color(0xFFFBBF24) : const Color(0xFF60A5FA),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entry.name,
                style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              entry.formattedSize,
              style: const TextStyle(color: Color(0xFF555555), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  IconData _fileIcon(String ext) {
    return switch (ext) {
      'dart' || 'py' || 'js' || 'ts' || 'go' || 'rs' || 'c' || 'cpp' => Icons.code,
      'json' || 'yaml' || 'yml' || 'toml' || 'xml' => Icons.data_object,
      'md' || 'txt' || 'log' => Icons.article,
      'sh' || 'bash' || 'zsh' => Icons.terminal,
      _ => Icons.insert_drive_file,
    };
  }
}
