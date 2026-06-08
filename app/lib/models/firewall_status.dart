enum FirewallType { ufw, iptables, nftables, none }

class FirewallStatus {
  final FirewallType type;
  final bool enabled;
  final String? defaultInboundPolicy;
  final List<FirewallRule> rules;

  const FirewallStatus({
    required this.type,
    required this.enabled,
    this.defaultInboundPolicy,
    required this.rules,
  });

  static const _kNone = FirewallStatus(
    type: FirewallType.none,
    enabled: false,
    rules: [],
  );

  factory FirewallStatus.fromShellOutput(String output) {
    if (output.contains('__NO_FIREWALL__')) return _kNone;
    if (output.contains('Status: active') || output.contains('Status: inactive')) {
      return _parseUfw(output);
    }
    if (output.contains('*filter') ||
        RegExp(r'-A (INPUT|OUTPUT|FORWARD)').hasMatch(output)) {
      return _parseIptables(output);
    }
    if (output.contains('hook input') && output.contains('chain')) {
      return _parseNft(output);
    }
    return _kNone;
  }

  static FirewallStatus _parseUfw(String output) {
    final enabled = output.contains('Status: active');
    String? defaultPolicy;
    final rules = <FirewallRule>[];
    for (final line in output.split('\n')) {
      final t = line.trim();
      if (t.startsWith('Default:')) {
        final m = RegExp(r'Default: (\w+) \(incoming\)').firstMatch(t);
        defaultPolicy = m?.group(1)?.toUpperCase();
      }
      final m = RegExp(r'^\[\s*\d+\]\s+(.+?)\s{2,}(ALLOW|DENY|LIMIT|REJECT)\s').firstMatch(t);
      if (m != null) {
        rules.add(FirewallRule(description: t, action: m.group(2), chain: null));
      }
    }
    return FirewallStatus(
      type: FirewallType.ufw,
      enabled: enabled,
      defaultInboundPolicy: defaultPolicy,
      rules: rules,
    );
  }

  static FirewallStatus _parseIptables(String output) {
    String? defaultPolicy;
    final rules = <FirewallRule>[];
    bool inFilter = false;
    for (final line in output.split('\n')) {
      final t = line.trim();
      if (t == '*filter') {
        inFilter = true;
        continue;
      }
      if (t == 'COMMIT') {
        inFilter = false;
        continue;
      }
      if (!inFilter) continue;
      final chain = RegExp(r'^:INPUT (\w+)').firstMatch(t);
      if (chain != null) defaultPolicy = chain.group(1);
      final rule = RegExp(r'^-A (\w+) .+ -j (\w+)').firstMatch(t);
      if (rule != null) {
        rules.add(FirewallRule(
          description: t,
          action: rule.group(2),
          chain: rule.group(1),
        ));
      }
    }
    return FirewallStatus(
      type: FirewallType.iptables,
      enabled: true,
      defaultInboundPolicy: defaultPolicy,
      rules: rules,
    );
  }

  static FirewallStatus _parseNft(String output) {
    final policyMatch = RegExp(r'hook input[^;]*;\s*policy (\w+);').firstMatch(output);
    final defaultPolicy = policyMatch?.group(1)?.toUpperCase();
    final rules = <FirewallRule>[];
    for (final line in output.split('\n')) {
      final t = line.trim();
      if (t.isEmpty ||
          t.startsWith('table') ||
          t.startsWith('chain') ||
          t.startsWith('type') ||
          t == '{' ||
          t == '}') {
        continue;
      }
      if (t.contains('accept') || t.contains('drop') || t.contains('reject')) {
        final action = t.contains('accept')
            ? 'ACCEPT'
            : t.contains('drop')
                ? 'DROP'
                : 'REJECT';
        rules.add(FirewallRule(description: t, action: action, chain: 'input'));
      }
    }
    return FirewallStatus(
      type: FirewallType.nftables,
      enabled: true,
      defaultInboundPolicy: defaultPolicy,
      rules: rules,
    );
  }
}

class FirewallRule {
  final String description;
  final String? action;
  final String? chain;

  const FirewallRule({
    required this.description,
    this.action,
    this.chain,
  });
}
