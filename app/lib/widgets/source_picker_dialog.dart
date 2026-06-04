import 'package:flutter/material.dart';

import '../models/host.dart';
import '../models/panel_source.dart';

/// Picker for an SFTP panel slot's source: the local filesystem (pinned
/// first) or any saved host. Pops a [PanelSource], or null when dismissed.
class SourcePickerDialog extends StatelessWidget {
  final List<Host> hosts;
  final PanelSource? current;

  const SourcePickerDialog({super.key, required this.hosts, this.current});

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
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFF2A2A2A)))),
              child: Row(children: [
                const Icon(Icons.dns_outlined, size: 15, color: Color(0xFF888888)),
                const SizedBox(width: 8),
                const Text('Select Source',
                    style: TextStyle(
                        color: Color(0xFFD4D4D4),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, size: 14, color: Color(0xFF555555))),
              ]),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView(
                shrinkWrap: true,
                children: [
                  _SourceTile(
                    icon: Icons.laptop_mac,
                    title: 'Local',
                    subtitle: 'This computer',
                    active: current is LocalSource,
                    onTap: () => Navigator.pop(context, const LocalSource()),
                  ),
                  for (final h in hosts)
                    _SourceTile(
                      icon: Icons.dns,
                      title: h.label,
                      subtitle: '${h.username}@${h.host}:${h.port}',
                      active: current is HostSource &&
                          (current as HostSource).host.id == h.id,
                      onTap: () => Navigator.pop(context, HostSource(h)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;
  final VoidCallback onTap;

  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: active ? const Color(0xFF22C55E).withValues(alpha: 0.08) : Colors.transparent,
        child: Row(children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14, color: const Color(0xFF22C55E)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: active ? const Color(0xFF22C55E) : const Color(0xFFD4D4D4),
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
                Text(subtitle,
                    style: const TextStyle(
                        color: Color(0xFF555555), fontSize: 11, fontFamily: 'monospace')),
              ],
            ),
          ),
          if (active) const Icon(Icons.check, size: 14, color: Color(0xFF22C55E)),
        ]),
      ),
    );
  }
}
