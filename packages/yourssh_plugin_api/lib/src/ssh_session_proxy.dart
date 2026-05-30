class SSHSessionProxy {
  final String sessionId;
  final String hostLabel;
  final bool isConnected;

  const SSHSessionProxy({
    required this.sessionId,
    required this.hostLabel,
    required this.isConnected,
  });
}
