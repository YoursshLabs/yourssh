import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/discovered_host.dart';
import '../models/host.dart';
import '../providers/host_provider.dart';
import '../providers/session_provider.dart';
import '../services/network_discovery_service.dart';
import '../theme/app_theme.dart';
import 'host_detail_panel.dart';

class NetworkDiscoverySheet extends StatefulWidget {
  /// When true, tapping a row calls [onSelected] and closes the sheet.
  final bool selectionMode;
  final void Function(DiscoveredHost)? onSelected;

  const NetworkDiscoverySheet({
    super.key,
    this.selectionMode = false,
    this.onSelected,
  });

  static void show(
    BuildContext context, {
    bool selectionMode = false,
    void Function(DiscoveredHost)? onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NetworkDiscoverySheet(
        selectionMode: selectionMode,
        onSelected: onSelected,
      ),
    );
  }

  @override
  State<NetworkDiscoverySheet> createState() => NetworkDiscoverySheetState();
}

class NetworkDiscoverySheetState extends State<NetworkDiscoverySheet> {
  final _svc = NetworkDiscoveryService();
  final _results = <String, DiscoveredHost>{};
  late final TextEditingController _subnetCtrl;

  List<SubnetInfo> _subnets = [];
  SubnetInfo? _selected;
  bool _editingSubnet = false;
  String? _subnetError;

  bool _scanning = false;
  int _scanned = 0;
  int _total = 0;
  String? _subnetsError;
  String? _scanError;

  StreamSubscription<DiscoveredHost>? _sub;

  // fix #8: derive counts from _results instead of maintaining separate counters
  // that diverge when hosts are merged from multiple sources
  int get _mdnsCount => _results.values
      .where((h) =>
          h.source == DiscoverySource.mdns ||
          h.source == DiscoverySource.both)
      .length;
  int get _tcpCount => _results.values
      .where((h) =>
          h.source == DiscoverySource.tcpScan ||
          h.source == DiscoverySource.both)
      .length;

  @override
  void initState() {
    super.initState();
    _subnetCtrl = TextEditingController();
    _loadSubnets();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _svc.cancel();
    _subnetCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSubnets() async {
    try {
      final subnets = await _svc.getLocalSubnets();
      if (!mounted) return;
      setState(() {
        _subnets = subnets;
        _selected = subnets.isNotEmpty ? subnets.first : null;
        if (_selected != null) {
          _subnetCtrl.text = _selected!.subnet;
        }
      });
      if (_selected != null) _startScan();
    } catch (e) {
      debugPrint('[NetworkDiscoverySheet] failed to list network interfaces: $e');
      if (mounted) setState(() => _subnetsError = e.toString());
    }
  }

  void _startScan() {
    if (_selected == null) return;
    _sub?.cancel();
    _svc.cancel();

    final subnetStr = _subnetCtrl.text.trim();
    final subnet = _editingSubnet
        ? SubnetInfo(
            interfaceName: _selected!.interfaceName,
            displayName: _selected!.displayName,
            address: _selected!.address,
            subnet: subnetStr,
          )
        : _selected!;

    setState(() {
      _scanning = true;
      _scanned = 0;
      _total = 0;
      _scanError = null;
      _results.clear();
    });

    _sub = _svc
        .scan(subnet, onProgress: (s, t) {
          if (mounted) setState(() { _scanned = s; _total = t; });
        })
        .listen(
          (h) {
            if (!mounted) return;
            // fix #8: just update _results; counters are derived
            setState(() => _results[h.ip] = h);
          },
          onDone: () { if (mounted) setState(() => _scanning = false); },
          onError: (e) {
            debugPrint('[NetworkDiscoverySheet] scan error: $e');
            if (mounted) setState(() { _scanning = false; _scanError = e.toString(); });
          },
        );
  }

  void _stopScan() {
    _sub?.cancel();
    _svc.cancel();
    if (mounted) setState(() => _scanning = false);
  }

  void _onAdd(BuildContext context, DiscoveredHost h) {
    // fix #6: use the modal's own context (panelCtx) for close navigation
    // so that if HostDetailPanel opens a sub-dialog, close still targets the panel
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (panelCtx) => HostDetailPanel(
        existing: null,
        initialHost: h.ip,
        initialPort: h.preferredPort, // fix #9
        initialLabel: h.hostname,
        initialProtocol: h.isRdp ? HostProtocol.rdp : HostProtocol.ssh,
        onClose: () => Navigator.of(panelCtx).pop(),
        onSave: (host, password) async {
          // fix #5: check mounted before using context after async gap
          if (!context.mounted) return;
          await context.read<HostProvider>().addHost(host, password: password);
          if (context.mounted) {
            Navigator.of(context).pop(); // close HostDetailPanel
            Navigator.of(context).pop(); // close DiscoverySheet
          }
        },
      ),
    );
  }

  Future<void> _onConnect(BuildContext context, DiscoveredHost h) async {
    // fix #1: capture providers BEFORE pop, move pop AFTER await so
    // context.mounted is still true when connectAny is called
    final hostProvider = context.read<HostProvider>();
    final sessionProvider = context.read<SessionProvider>();

    final host = Host(
      id: const Uuid().v4(),
      label: h.hostname ?? h.ip,
      host: h.ip,
      port: h.preferredPort, // fix #9
      username: '',
      protocol: h.isRdp ? HostProtocol.rdp : HostProtocol.ssh,
      createdAt: DateTime.now(),
    );
    await hostProvider.addHost(host);
    if (context.mounted) {
      Navigator.of(context).pop();
      sessionProvider.connectAny(host);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            _buildHandle(),
            _buildHeader(context),
            _buildSubnetBar(),
            if (_scanning) _buildProgress(),
            _buildCounterRow(),
            const Divider(color: AppColors.border, height: 1),
            Expanded(child: _buildResultList(context, scroll)),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() => Center(
        child: Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _buildHeader(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
        child: Row(
          children: [
            const Icon(Icons.wifi_find, color: AppColors.accent, size: 18),
            const SizedBox(width: 8),
            const Text(
              'Discover Devices',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: AppColors.textSecondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );

  Widget _buildSubnetBar() {
    if (_subnetsError != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Text(
          'Failed to list interfaces: $_subnetsError',
          style: TextStyle(color: Colors.red.shade300, fontSize: 13),
        ),
      );
    }
    if (_subnets.isEmpty && _selected == null) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Text(
          'No active network interfaces found.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: [
          if (_subnets.length > 1)
            DropdownButton<SubnetInfo>(
              value: _selected,
              dropdownColor: AppColors.card,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              underline: const SizedBox(),
              items: _subnets
                  .map((s) => DropdownMenuItem(value: s, child: Text(s.displayName)))
                  .toList(),
              onChanged: (s) {
                if (s == null) return;
                setState(() {
                  _selected = s;
                  _subnetCtrl.text = s.subnet;
                  _editingSubnet = false;
                  _subnetError = null;
                });
              },
            )
          else
            Text(
              _selected?.displayName ?? '',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _subnetCtrl,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontFamily: 'monospace'),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                errorText: _subnetError,
                errorStyle: const TextStyle(fontSize: 10),
              ),
              onChanged: (v) {
                setState(() {
                  _editingSubnet = true;
                  _subnetError = SubnetInfo.validateSubnet(v);
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _subnetError != null
                ? null
                : () {
                    if (_scanning) _stopScan();
                    _startScan();
                  },
            child: Text(
              _scanning ? 'Restart' : 'Scan',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress() {
    final progress = _total > 0 ? _scanned / _total : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.border,
            color: AppColors.accent,
          ),
          const SizedBox(height: 4),
          Text(
            _total > 0 ? 'Scanning… $_scanned / $_total' : 'Starting…',
            style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildCounterRow() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Text(
          'mDNS: $_mdnsCount found · TCP scan: $_tcpCount found',
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
        ),
      );

  Widget _buildResultList(BuildContext context, ScrollController scroll) {
    final items = _results.values.toList()
      ..sort((a, b) => a.ip.compareTo(b.ip));
    if (items.isEmpty && _scanError != null && !_scanning) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Scan failed: $_scanError',
            style: TextStyle(color: Colors.red.shade300),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'No devices found yet…',
          style: TextStyle(color: AppColors.textTertiary),
        ),
      );
    }
    return ListView.builder(
      controller: scroll,
      itemCount: items.length,
      itemBuilder: (ctx, i) => _DiscoveredRow(
        host: items[i],
        selectionMode: widget.selectionMode,
        onSelect: () {
          widget.onSelected?.call(items[i]);
          Navigator.of(context).pop();
        },
        onAdd: () => _onAdd(context, items[i]),
        onConnect: () => _onConnect(context, items[i]),
      ),
    );
  }
}

class _DiscoveredRow extends StatelessWidget {
  final DiscoveredHost host;
  final bool selectionMode;
  final VoidCallback onSelect;
  final VoidCallback onAdd;
  final VoidCallback onConnect;

  const _DiscoveredRow({
    required this.host,
    required this.selectionMode,
    required this.onSelect,
    required this.onAdd,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: selectionMode ? onSelect : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            Icon(
              host.isRdp ? Icons.desktop_windows : Icons.computer,
              size: 16,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    host.hostname ?? host.ip,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13),
                  ),
                  if (host.hostname != null)
                    Text(
                      host.ip,
                      style: const TextStyle(
                          color: AppColors.textTertiary, fontSize: 11),
                    ),
                ],
              ),
            ),
            _Badge(host.portLabel),
            if (!selectionMode) ...[
              const SizedBox(width: 8),
              _SmallBtn('Add', onAdd),
              const SizedBox(width: 4),
              _SmallBtn('Connect', onConnect, primary: true),
            ],
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  const _Badge(this.label);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
      );
}

class _SmallBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;

  const _SmallBtn(this.label, this.onTap, {this.primary = false});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: primary ? AppColors.accent : AppColors.card,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: primary ? AppColors.accent : AppColors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: primary ? Colors.white : AppColors.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
}
