import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../models/host.dart';
import '../models/local_entry.dart';
import '../models/panel_source.dart';
import '../models/sftp_entry.dart';
import '../models/sftp_transfer_item.dart';
import '../providers/host_provider.dart';
import '../providers/local_file_panel_provider.dart';
import '../providers/sftp_panel_provider.dart';
import '../providers/sftp_transfer_provider.dart';
import '../services/app_discovery_service.dart';
import '../services/external_edit_service.dart';
import '../services/local_copy_service.dart';
import '../services/sftp_file_ops_service.dart';
import '../services/sftp_transfer_service.dart';
import '../services/ssh_service.dart';
import 'local_file_panel.dart';
import 'sftp_panel.dart';
import 'sftp_transfer_panel.dart';
import 'source_picker_dialog.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

/// Two-panel commander layout. Each slot points at a [PanelSource] (the
/// local filesystem or any saved host) and can be switched at any time.
/// Left defaults to Local; right starts unconnected.
/// Design: docs/superpowers/specs/2026-06-04-sftp-two-panel-design.md
class DualPanelSftpScreen extends StatefulWidget {
  final ValueNotifier<bool> connectionNotifier;

  /// Whether the SFTP tab is currently visible. The screen stays mounted
  /// offstage (KeepAliveOffstage, issue #42), so listings can go stale while
  /// hidden (e.g. the host's pooled SSH client was closed with its last
  /// terminal); flipping back to active triggers a reload of both slots.
  final bool active;

  const DualPanelSftpScreen({
    super.key,
    required this.connectionNotifier,
    this.active = true,
  });

  @override
  State<DualPanelSftpScreen> createState() => _DualPanelSftpScreenState();
}

class _DualPanelSftpScreenState extends State<DualPanelSftpScreen> {
  PanelSource? _sourceLeft = const LocalSource();
  PanelSource? _sourceRight;

  // Each slot owns one provider of each kind, and the last browsed remote
  // path is remembered per host in [_remotePathByHost] — switching a slot's
  // source away and back resumes both local and remote panels where the
  // user left off.
  final Map<String, String> _remotePathByHost = {};
  late final LocalFilePanelProvider _localLeft;
  late final LocalFilePanelProvider _localRight;
  late final SftpPanelProvider _sftpLeft;
  late final SftpPanelProvider _sftpRight;
  late final SftpTransferProvider _transferProvider;
  // Owned by the State (not created inside build) so the State's own methods
  // can use them directly: `context.read` from the State's context cannot see
  // providers created below it in build().
  late final SftpTransferService _transferService;
  late final SftpFileOpsService _fileOpsService;
  late final ExternalEditService _externalEditService;
  late final AppDiscoveryService _appDiscoveryService;
  final _localCopyService = LocalCopyService();
  // Owned here so the transfer buttons can follow the resizable gutter.
  final FResizableController _resizeController = FResizableController();

  @override
  void initState() {
    super.initState();
    _localLeft = LocalFilePanelProvider();
    _localRight = LocalFilePanelProvider();
    _sftpLeft = SftpPanelProvider();
    _sftpRight = SftpPanelProvider();
    _transferProvider = SftpTransferProvider();
    final ssh = context.read<SshService>();
    _transferService = SftpTransferService(ssh);
    _fileOpsService = SftpFileOpsService(ssh);
    _externalEditService = ExternalEditService(_transferService);
    _appDiscoveryService = AppDiscoveryService();
    widget.connectionNotifier.value = false;
  }

  @override
  void didUpdateWidget(DualPanelSftpScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      // Returning to the SFTP tab — listings may be stale (host client
      // closed, files changed) while we were offstage.
      _reloadSlot(true);
      _reloadSlot(false);
    }
  }

  @override
  void dispose() {
    widget.connectionNotifier.value = false;
    _externalEditService.dispose();
    _appDiscoveryService.dispose();
    _localLeft.dispose();
    _localRight.dispose();
    _sftpLeft.dispose();
    _sftpRight.dispose();
    _transferProvider.dispose();
    _resizeController.dispose();
    super.dispose();
  }

  // ── Slot helpers ──────────────────────────────────────

  PanelSource? _sourceOf(bool left) => left ? _sourceLeft : _sourceRight;
  LocalFilePanelProvider _localOf(bool left) => left ? _localLeft : _localRight;
  SftpPanelProvider _sftpOf(bool left) => left ? _sftpLeft : _sftpRight;

  Future<void> _pickSource(bool left) async {
    final hosts = context.read<HostProvider>().allHosts;
    final picked = await showYsDialog<PanelSource>(
      context,
      builder: (_) => SourcePickerDialog(hosts: hosts, current: _sourceOf(left)),
    );
    if (!mounted || picked == null || picked == _sourceOf(left)) return;
    // Remember where the user was on the host being switched away from, so
    // picking it again (in either slot) resumes at that path.
    final old = _sourceOf(left);
    if (old is HostSource) {
      _remotePathByHost[old.host.id] = _sftpOf(left).currentPath;
    }
    setState(() {
      if (left) {
        _sourceLeft = picked;
      } else {
        _sourceRight = picked;
      }
      widget.connectionNotifier.value =
          _sourceLeft is HostSource || _sourceRight is HostSource;
    });
  }

  Future<void> _reloadSlot(bool left) async {
    if (!mounted) return;
    final src = _sourceOf(left);
    if (src is LocalSource) {
      await _localOf(left).reload();
    } else if (src is HostSource) {
      final prov = _sftpOf(left);
      prov.setLoadState(SftpPanelLoadState.loading);
      try {
        final entries =
            await _transferService.listDirectory(src.host, prov.currentPath);
        prov..setEntries(entries)..setLoadState(SftpPanelLoadState.loaded);
      } catch (e) {
        prov.setLoadState(SftpPanelLoadState.error, error: e.toString());
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    AppSnack.error(context, message);
  }

  // ── Transfer dispatch ─────────────────────────────────

  /// Moves [localEntries]/[sftpEntries] (or, when null, the source slot's
  /// current selection) toward the opposite slot.
  Future<void> _transfer({
    required bool fromLeft,
    List<LocalEntry>? localEntries,
    List<SftpEntry>? sftpEntries,
  }) async {
    final src = _sourceOf(fromLeft);
    final dst = _sourceOf(!fromLeft);
    if (src == null || dst == null) return;

    switch (transferKindFor(src, dst)) {
      case TransferKind.localCopy:
        await _localToLocal(fromLeft, entries: localEntries);
      case TransferKind.upload:
        await _upload(fromLeft, (dst as HostSource).host,
            entries: localEntries);
      case TransferKind.download:
        await _download(fromLeft, (src as HostSource).host,
            entries: sftpEntries);
      case TransferKind.remoteRelay:
        await _relay(fromLeft, (src as HostSource).host,
            (dst as HostSource).host, entries: sftpEntries);
    }
  }

  // Local slot → local slot: plain filesystem copy.
  Future<void> _localToLocal(bool fromLeft, {List<LocalEntry>? entries}) async {
    final selected = entries ?? _localOf(fromLeft).selectedEntries.toList();
    if (selected.isEmpty) return;
    final dstDir = _localOf(!fromLeft).currentPath;

    final items = [
      for (final e in selected)
        SftpTransferItem(fileName: e.name, direction: TransferDirection.upload)
          ..totalBytes = e.size,
    ];
    _transferProvider.startBatch(items);

    var skipped = 0;
    try {
      for (int i = 0; i < selected.length; i++) {
        if (_transferProvider.isCancelled) break;
        final item = items[i];
        _transferProvider.updateItem(item.id, status: TransferStatus.inProgress);
        var copied = 0;
        await _localCopyService.copyEntry(
          selected[i].path,
          dstDir,
          onBytes: (n) {
            copied += n;
            _transferProvider.updateItem(item.id, bytesTransferred: copied);
          },
          onSkipped: (_) => skipped++,
        );
        _transferProvider.updateItem(item.id, status: TransferStatus.done);
      }
    } on ArgumentError catch (e) {
      _showError(e.message?.toString() ?? 'Copy rejected');
    } catch (e) {
      _showError('Copy failed: $e');
    } finally {
      if (skipped > 0) {
        _showError('Skipped $skipped existing file(s) — not overwritten');
      }
      await _reloadSlot(!fromLeft);
    }
  }

  // Local slot → remote slot.
  Future<void> _upload(bool fromLeft, Host host,
      {List<LocalEntry>? entries}) async {
    final selected = entries ?? _localOf(fromLeft).selectedEntries.toList();
    if (selected.isEmpty) return;
    final service = _transferService;
    final remoteDir = _sftpOf(!fromLeft).currentPath;

    final items = [
      for (final e in selected)
        SftpTransferItem(fileName: e.name, direction: TransferDirection.upload)
          ..totalBytes = e.size,
    ];
    _transferProvider.startBatch(items);

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
      _showError('Upload failed: $e');
    } finally {
      await _reloadSlot(!fromLeft);
    }
  }

  // Remote slot → local slot.
  Future<void> _download(bool fromLeft, Host host,
      {List<SftpEntry>? entries}) async {
    final selected = entries ?? _sftpOf(fromLeft).selectedEntries.toList();
    if (selected.isEmpty) return;
    final service = _transferService;
    final localDir = _localOf(!fromLeft).currentPath;

    final items = [
      for (final e in selected)
        SftpTransferItem(fileName: e.name, direction: TransferDirection.download)
          ..totalBytes = e.size,
    ];
    _transferProvider.startBatch(items);

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
      _showError('Download failed: $e');
    } finally {
      await _reloadSlot(!fromLeft);
    }
  }

  // Remote slot → remote slot, relayed through a local temp file (files only).
  Future<void> _relay(bool fromLeft, Host srcHost, Host dstHost,
      {List<SftpEntry>? entries}) async {
    var selected = (entries ?? _sftpOf(fromLeft).selectedEntries.toList())
        .where((e) => !e.isDirectory)
        .toList();
    final service = _transferService;
    final destDir = _sftpOf(!fromLeft).currentPath;

    // A same-host relay into the file's own directory would truncate and
    // rewrite it in place (the upload opens with truncate) — refuse it the
    // same way LocalCopyService refuses same-directory copies.
    if (srcHost.id == dstHost.id) {
      final before = selected.length;
      selected = selected
          .where((e) => p.posix.dirname(e.path) != destDir)
          .toList();
      if (selected.length < before) {
        _showError(selected.isEmpty
            ? 'Source and destination folders are the same'
            : 'Skipped ${before - selected.length} file(s) already in the '
                'destination folder');
      }
    }
    if (selected.isEmpty) return;

    final items = [
      for (final e in selected)
        SftpTransferItem(fileName: e.name, direction: TransferDirection.upload)
          ..totalBytes = e.size,
    ];
    _transferProvider.startBatch(items);

    try {
      for (int i = 0; i < selected.length; i++) {
        if (_transferProvider.isCancelled) break;
        final item = items[i];
        final entry = selected[i];
        _transferProvider.updateItem(item.id, status: TransferStatus.inProgress);
        final tmp = await service.downloadToTemp(srcHost, entry);
        if (tmp != null) {
          await service.copyLocalToRemote(localPath: tmp, remoteHost: dstHost, remoteDir: destDir);
          await File(tmp).delete();
        }
        _transferProvider.updateItem(item.id, bytesTransferred: entry.size, status: TransferStatus.done);
      }
    } catch (e) {
      _showError('Copy failed: $e');
    } finally {
      await _reloadSlot(!fromLeft);
    }
  }

  /// Whether the slot has a selection the transfer matrix can move toward
  /// the other slot.
  bool _canTransferFrom(bool fromLeft) {
    final src = _sourceOf(fromLeft);
    final dst = _sourceOf(!fromLeft);
    if (src == null || dst == null) return false;
    return switch (transferKindFor(src, dst)) {
      TransferKind.localCopy ||
      TransferKind.upload =>
        _localOf(fromLeft).selectedEntries.isNotEmpty,
      TransferKind.download => _sftpOf(fromLeft).selectedEntries.isNotEmpty,
      TransferKind.remoteRelay =>
        _sftpOf(fromLeft).selectedEntries.any((e) => !e.isDirectory),
    };
  }

  /// Why a context-menu copy-to-target from [fromLeft] cannot run for an
  /// entry of [isDirectory] (null = it can). Mirrors the transfer matrix:
  /// remote→remote relays are file-only, and a copy into the directory the
  /// entry already lives in can never succeed (the transfer layer rejects
  /// it), so the item is disabled up front instead of failing on click.
  String? _copyBlockReason(bool fromLeft, {required bool isDirectory}) {
    final src = _sourceOf(fromLeft);
    final dst = _sourceOf(!fromLeft);
    if (src == null || dst == null) return 'No target panel';
    if (isDirectory &&
        transferKindFor(src, dst) == TransferKind.remoteRelay) {
      return 'Folders not supported between two remote hosts';
    }
    if (_sameDirectory(src, dst, fromLeft)) {
      return 'Both panels show this folder';
    }
    return null;
  }

  /// True when both panels currently display the same directory of the
  /// same source (local↔local on one path, or the same host on one path).
  bool _sameDirectory(PanelSource src, PanelSource dst, bool fromLeft) {
    if (src is LocalSource && dst is LocalSource) {
      return _localOf(fromLeft).currentPath ==
          _localOf(!fromLeft).currentPath;
    }
    if (src is HostSource && dst is HostSource) {
      return src.host.id == dst.host.id &&
          _sftpOf(fromLeft).currentPath == _sftpOf(!fromLeft).currentPath;
    }
    return false;
  }

  // ── Drag & drop ───────────────────────────────────────

  // A dropped entry is treated as coming from the opposite slot and is
  // passed to the transfer explicitly — never via the panels' selection
  // state, which a drop must not disturb. Dropping an entry back onto its
  // own panel resolves to a same-directory copy, which the transfer guards
  // reject with a message.
  Future<void> _onDropLocalEntry(bool targetLeft, LocalEntry entry) async {
    if (entry.isDirectory) return;
    if (_sourceOf(!targetLeft) is! LocalSource) return;
    await _transfer(fromLeft: !targetLeft, localEntries: [entry]);
  }

  Future<void> _onDropSftpEntry(bool targetLeft, SftpEntry entry) async {
    if (entry.isDirectory) return;
    if (_sourceOf(!targetLeft) is! HostSource) return;
    await _transfer(fromLeft: !targetLeft, sftpEntries: [entry]);
  }

  // ── Build ─────────────────────────────────────────────

  Widget _slot(bool left) {
    final src = _sourceOf(left);
    final Widget panel;
    if (src is LocalSource) {
      panel = LocalFilePanel(
        provider: _localOf(left),
        onChangeSource: () => _pickSource(left),
        onCopyToTarget: (entry) =>
            _transfer(fromLeft: left, localEntries: [entry]),
        copyToTargetBlockReason: (entry) =>
            _copyBlockReason(left, isDirectory: entry.isDirectory),
      );
    } else {
      final host = src is HostSource ? src.host : null;
      panel = SftpPanel(
        key: ValueKey('${left ? 'l' : 'r'}_${host?.id}'),
        host: host,
        panelId: left ? 'remote_left' : 'remote_right',
        provider: _sftpOf(left),
        onChangeHost: () => _pickSource(left),
        initialPath:
            host == null ? '/' : (_remotePathByHost[host.id] ?? '/'),
        onCopyToTarget: (entry) =>
            _transfer(fromLeft: left, sftpEntries: [entry]),
        copyToTargetBlockReason: (entry) =>
            _copyBlockReason(left, isDirectory: entry.isDirectory),
      );
    }

    return DragTarget<LocalEntry>(
      onAcceptWithDetails: (d) => _onDropLocalEntry(left, d.data),
      builder: (_, localCandidates, _) => DragTarget<SftpEntry>(
        onAcceptWithDetails: (d) => _onDropSftpEntry(left, d.data),
        builder: (_, sftpCandidates, _) {
          final dropping =
              localCandidates.isNotEmpty || sftpCandidates.isNotEmpty;
          return DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(YsRadius.card),
              border: dropping
                  ? Border.all(
                      color: YsColors.primary.withValues(alpha: 0.4),
                      width: 2)
                  : Border.all(color: YsColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(YsRadius.card),
              child: ColoredBox(color: YsColors.card, child: panel),
            ),
          );
        },
      ),
    );
  }

  /// One resizable half: the slot plus its half of the gutter that holds
  /// the transfer buttons ([_TransferBar.width] split evenly).
  FResizableRegion _region(bool left) => FResizableRegion.flex(
        flex: 20,
        minFlex: 7,
        builder: (_, _, child) => Padding(
          padding: left
              ? const EdgeInsets.only(right: _TransferBar.width / 2)
              : const EdgeInsets.only(left: _TransferBar.width / 2),
          child: child,
        ),
        child: _slot(left),
      );

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SftpTransferService>.value(value: _transferService),
        Provider<SftpFileOpsService>.value(value: _fileOpsService),
        Provider<ExternalEditService>.value(value: _externalEditService),
        Provider<AppDiscoveryService>.value(value: _appDiscoveryService),
        ChangeNotifierProvider.value(value: _transferProvider),
      ],
      child: ListenableBuilder(
        listenable:
            Listenable.merge([_localLeft, _localRight, _sftpLeft, _sftpRight]),
        builder: (context, _) => Column(
          children: [
            Expanded(
              // The two slots split the width evenly and can be resized by
              // dragging the gutter between them; the transfer buttons sit
              // in that gutter and follow it.
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  children: [
                    FResizable(
                      axis: Axis.horizontal,
                      control: FResizableControl.managed(
                          controller: _resizeController),
                      divider: FResizableDivider.none,
                      // Kept inside the gutter so it never covers the panels.
                      hitRegionExtent: _TransferBar.width / 3,
                      crossAxisExtent: constraints.maxHeight,
                      children: [_region(true), _region(false)],
                    ),
                    // Laid out after FResizable (a positioned child), so it
                    // reads the regions FResizable has just laid out, also
                    // right after a window resize rescaled them.
                    Positioned.fill(
                      child: ListenableBuilder(
                        listenable: _resizeController,
                        builder: (context, _) => LayoutBuilder(
                          builder: (context, box) {
                            final regions = _resizeController.regions;
                            final boundary = regions.isEmpty
                                ? box.maxWidth / 2
                                : regions.first.offset.max;
                            return Stack(
                              children: [
                                Positioned(
                                  left: boundary - _TransferBar.width / 2,
                                  top: 0,
                                  bottom: 0,
                                  width: _TransferBar.width,
                                  child: _TransferBar(
                                    canLeft: _canTransferFrom(false),
                                    canRight: _canTransferFrom(true),
                                    onLeft: () => _transfer(fromLeft: false),
                                    onRight: () => _transfer(fromLeft: true),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Docked, minimizable transfer progress — non-modal so the
            // workspace stays usable while batches run (and more can be
            // queued; SftpTransferProvider.startBatch appends).
            const SftpTransferPanel(),
          ],
        ),
      ),
    );
  }
}

/// Copy → / Copy ← buttons centred in the gutter between the slots. Only
/// the buttons take pointer events, so the rest of the gutter stays a
/// resize handle.
class _TransferBar extends StatelessWidget {
  static const double width = 36;

  final bool canLeft;
  final bool canRight;
  final VoidCallback onLeft;
  final VoidCallback onRight;

  const _TransferBar({
    required this.canLeft,
    required this.canRight,
    required this.onLeft,
    required this.onRight,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(FLucideIcons.arrowRight, 'Copy →', canRight ? onRight : null),
          const SizedBox(height: YsSpace.s2),
          _button(FLucideIcons.arrowLeft, 'Copy ←', canLeft ? onLeft : null),
        ],
      ),
    );
  }

  Widget _button(IconData icon, String tooltip, VoidCallback? onPress) =>
      Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: FButton.icon(
          variant: onPress == null ? .outline : .secondary,
          size: .xs,
          semanticsLabel: tooltip,
          onPress: onPress,
          child: Icon(icon,
              color: onPress == null ? null : YsColors.accentText),
        ),
      );
}
