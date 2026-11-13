import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import '../models/host.dart';

/// Small chip marking a remote-desktop host's protocol (RDP / VNC). One widget
/// shared by the dashboard cards, list rows, and the host detail header so a
/// restyle can't leave the call sites visually diverged. SSH renders nothing.
class ProtocolBadge extends StatelessWidget {
  const ProtocolBadge(this.protocol, {super.key});

  final HostProtocol protocol;

  @override
  Widget build(BuildContext context) => switch (protocol) {
    HostProtocol.rdp => const YsStatusBadge('RDP'),
    HostProtocol.vnc => const YsStatusBadge('VNC'),
    HostProtocol.ssh => const SizedBox.shrink(),
  };
}
