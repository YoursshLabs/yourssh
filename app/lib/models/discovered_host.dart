enum DiscoverySource { mdns, tcpScan, both }

class DiscoveredHost {
  final String ip;
  final String? hostname;
  final List<int> openPorts;
  final DiscoverySource source;
  final String? mdnsServiceType;

  const DiscoveredHost({
    required this.ip,
    this.hostname,
    required this.openPorts,
    required this.source,
    this.mdnsServiceType,
  });

  DiscoveredHost merge(DiscoveredHost other) {
    final ports = {...openPorts, ...other.openPorts}.toList()..sort();
    return DiscoveredHost(
      ip: ip,
      hostname: hostname ?? other.hostname,
      openPorts: ports,
      source: DiscoverySource.both,
      mdnsServiceType: mdnsServiceType ?? other.mdnsServiceType,
    );
  }

  String get portLabel {
    if (openPorts.isEmpty) return '?';
    if (openPorts.contains(3389)) return 'RDP';
    if (openPorts.contains(22)) return 'SSH';
    if (openPorts.contains(2222)) return 'SSH:2222';
    return openPorts.first.toString();
  }

  bool get isRdp => openPorts.contains(3389) && !openPorts.contains(22);
}

class SubnetInfo {
  final String interfaceName;
  final String displayName;
  final String address;
  final String subnet;

  const SubnetInfo({
    required this.interfaceName,
    required this.displayName,
    required this.address,
    required this.subnet,
  });

  static String subnetFromAddress(String address) {
    final parts = address.split('.');
    return '${parts[0]}.${parts[1]}.${parts[2]}.0/24';
  }

  static List<String> hostsInSubnet(String subnet) {
    final base = subnet.split('/').first;
    final parts = base.split('.');
    final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
    return List.generate(254, (i) => '$prefix.${i + 1}');
  }

  /// Returns null when [subnet] is a valid x.x.x.x/y string.
  static String? validateSubnet(String subnet) {
    final parts = subnet.split('/');
    if (parts.length != 2) return 'Expected format: 192.168.1.0/24';
    final octets = parts[0].split('.');
    if (octets.length != 4) return 'Expected 4 octets';
    for (final o in octets) {
      final n = int.tryParse(o);
      if (n == null || n < 0 || n > 255) return 'Invalid octet: $o';
    }
    final prefix = int.tryParse(parts[1]);
    if (prefix == null || prefix < 1 || prefix > 32) return 'Prefix must be 1–32';
    return null;
  }

  @override
  String toString() => '$displayName ($address) — $subnet';
}
