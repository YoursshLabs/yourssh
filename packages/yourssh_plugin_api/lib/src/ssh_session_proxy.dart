class SSHSessionProxy {
  final String sessionId;
  final String hostLabel;
  final bool isConnected;
  final bool isActive;

  const SSHSessionProxy({
    required this.sessionId,
    required this.hostLabel,
    required this.isConnected,
    this.isActive = false,
  });
}
