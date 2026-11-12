import '../models/host.dart';
import 'ssh_service.dart';
import 'web_tools_service.dart';

class McpEndpoint {
  final Host host;
  final int localPort;
  final String mcpCommand;
  bool isRunning;

  /// PID of the remote process started for this endpoint (set by start()).
  int? pid;

  McpEndpoint({
    required this.host,
    required this.localPort,
    required this.mcpCommand,
    this.isRunning = false,
  });
}

class McpStartResult {
  final bool ok;
  final String? error;
  const McpStartResult.success() : ok = true, error = null;
  const McpStartResult.failure(this.error) : ok = false;
}

class McpGatewayService {
  final SshService _sshService;
  final Map<String, McpEndpoint> _endpoints = {};

  McpGatewayService(this._sshService);

  Future<McpStartResult> start(McpEndpoint endpoint) async {
    try {
      final remotePort = 9000 + endpoint.localPort;
      // `exec` makes the shell become the MCP process, so $! is its real PID.
      final inner = 'exec ${endpoint.mcpCommand} --port $remotePort';
      final cmd =
          'nohup sh -c ${WebToolsService.shellQuote(inner)} >/dev/null 2>&1 & echo \$!';
      final r = await _sshService.exec(endpoint.host, cmd, auditSource: 'devops');
      final pid = int.tryParse(r.stdout.trim().split('\n').last.trim());
      if (pid == null || pid <= 0) {
        return McpStartResult.failure(r.stderr.trim().isEmpty
            ? 'Could not start MCP server (no PID returned)'
            : r.stderr.trim());
      }
      endpoint.pid = pid;
      endpoint.isRunning = true;
      _endpoints[endpoint.host.id] = endpoint;
      return const McpStartResult.success();
    } catch (e) {
      return McpStartResult.failure(e.toString());
    }
  }

  Future<void> stop(Host host) async {
    final endpoint = _endpoints[host.id];
    if (endpoint == null) return;
    final pid = endpoint.pid;
    if (pid != null) {
      await _sshService.exec(host, 'kill $pid 2>/dev/null', auditSource: 'devops');
    }
    endpoint.isRunning = false;
    _endpoints.remove(host.id);
  }

  McpEndpoint? getEndpoint(String hostId) => _endpoints[hostId];
}
