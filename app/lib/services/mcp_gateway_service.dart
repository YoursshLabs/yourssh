import '../models/host.dart';
import 'ssh_service.dart';

class McpEndpoint {
  final Host host;
  final int localPort;
  final String mcpCommand;
  bool isRunning;

  McpEndpoint({
    required this.host,
    required this.localPort,
    required this.mcpCommand,
    this.isRunning = false,
  });
}

class McpGatewayService {
  final SshService _sshService;
  final Map<String, McpEndpoint> _endpoints = {};

  McpGatewayService(this._sshService);

  Future<bool> start(McpEndpoint endpoint) async {
    try {
      final remotePort = 9000 + endpoint.localPort;
      final cmd = '${endpoint.mcpCommand} --port $remotePort &';
      await _sshService.exec(endpoint.host, cmd);
      endpoint.isRunning = true;
      _endpoints[endpoint.host.id] = endpoint;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop(Host host) async {
    final endpoint = _endpoints[host.id];
    if (endpoint == null) return;
    final binary = endpoint.mcpCommand.split(' ').first.replaceAll("'", '');
    await _sshService.exec(host, "pkill -f '$binary'");
    endpoint.isRunning = false;
    _endpoints.remove(host.id);
  }

  McpEndpoint? getEndpoint(String hostId) => _endpoints[hostId];
}
