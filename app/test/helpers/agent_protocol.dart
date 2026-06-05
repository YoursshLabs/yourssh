import 'dart:typed_data';

/// Frames an agent-protocol message body with the 4-byte big-endian length
/// prefix — the wire format the SSH agent and `SystemAgentProxy` exchange.
/// Shared by the fake-agent test servers.
Uint8List agentMsg(List<int> body) {
  final header = Uint8List(4);
  ByteData.view(header.buffer).setUint32(0, body.length, Endian.big);
  return Uint8List.fromList([...header, ...body]);
}
