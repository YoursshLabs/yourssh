class PluginSSHException implements Exception {
  final String message;
  const PluginSSHException(this.message);

  @override
  String toString() => 'PluginSSHException: $message';
}
