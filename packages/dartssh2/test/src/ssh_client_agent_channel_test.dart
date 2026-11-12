import 'dart:async';
import 'dart:mirrors';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/message/msg_channel.dart';
import 'package:dartssh2/src/ssh_packet.dart';
import 'package:test/test.dart';

class _NoopAgent implements SSHAgentHandler {
  @override
  Future<Uint8List> handleRequest(Uint8List request) async =>
      Uint8List.fromList([5]);
}

/// Server-opened `auth-agent@openssh.com` channels must only be accepted
/// after this client sent an `auth-agent-req@openssh.com` the server accepted.
void main() {
  final clientLibrary = reflectClass(SSHClient).owner as LibraryMirror;
  final transportLibrary = reflectClass(SSHTransport).owner as LibraryMirror;

  /// Marks the key exchange as finished so replies are written to the socket
  /// instead of being queued behind the rekey buffer.
  void finishKex(SSHClient client) {
    final transport = reflect(client)
        .getField(MirrorSystem.getSymbol('_transport', clientLibrary))
        .reflectee;
    reflect(transport).setField(
      MirrorSystem.getSymbol('_kexInProgress', transportLibrary),
      false,
    );
  }

  void markAgentRequestAccepted(SSHClient client) {
    reflect(client).setField(
      MirrorSystem.getSymbol('_agentForwardingAccepted', clientLibrary),
      true,
    );
  }

  int replyMessageId(_Socket socket) {
    final packet = socket.packets.last;
    final length = SSHPacket.readPacketLength(packet);
    final padding = SSHPacket.readPaddingLength(packet);
    return Uint8List.sublistView(packet, 5, 4 + length - padding)[0];
  }

  void openAgentChannel(SSHClient client) {
    client.handlePacket(SSH_Message_Channel_Open(
      channelType: 'auth-agent@openssh.com',
      senderChannel: 7,
      initialWindowSize: 1024,
      maximumPacketSize: 1024,
    ).encode());
  }

  const confirmation = 91;
  const openFailure = 92;

  test('refuses agent channel when no auth-agent-req was accepted', () {
    final socket = _Socket();
    final client = SSHClient(socket, username: 'u', agentHandler: _NoopAgent());
    finishKex(client);

    openAgentChannel(client);

    expect(replyMessageId(socket), openFailure);
    client.close();
  });

  test('accepts agent channel after the server accepted auth-agent-req', () {
    final socket = _Socket();
    final client = SSHClient(socket, username: 'u', agentHandler: _NoopAgent());
    finishKex(client);
    markAgentRequestAccepted(client);

    openAgentChannel(client);

    expect(replyMessageId(socket), confirmation);
    client.close();
  });

  test('refuses agent channel without a handler', () {
    final socket = _Socket();
    final client = SSHClient(socket, username: 'u');
    finishKex(client);

    openAgentChannel(client);

    expect(replyMessageId(socket), openFailure);
    client.close();
  });
}

class _Socket implements SSHSocket {
  final _in = StreamController<Uint8List>();
  final _done = Completer<void>();
  final packets = <Uint8List>[];

  @override
  Stream<Uint8List> get stream => _in.stream;

  @override
  StreamSink<List<int>> get sink => _Sink(packets);

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  void destroy() {
    if (!_done.isCompleted) _done.complete();
  }
}

class _Sink implements StreamSink<List<int>> {
  _Sink(this._packets);
  final List<Uint8List> _packets;

  @override
  void add(List<int> data) => _packets.add(Uint8List.fromList(data));
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final c in stream) {
      add(c);
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> close() async {}
  @override
  Future<void> get done async {}
}
