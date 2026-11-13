import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/message/msg_channel.dart';
import 'package:dartssh2/src/ssh_channel.dart';
import 'package:test/test.dart';

/// A fast command's exit-status can arrive in the same packet burst as the
/// exec reply, i.e. before the caller's continuation has built the
/// [SSHSession] and installed its request handler. The status must not be lost.
void main() {
  test('exit-status received before the SSHSession exists is kept', () async {
    final controller = SSHChannelController(
      localId: 1,
      localMaximumPacketSize: 1024 * 1024,
      localInitialWindowSize: 1024 * 1024,
      remoteId: 2,
      remoteMaximumPacketSize: 1024 * 1024,
      remoteInitialWindowSize: 1024 * 1024,
      sendMessage: (_) {},
    );
    controller.handleMessage(SSH_Message_Channel_Data(
      recipientChannel: 1,
      data: Uint8List.fromList(utf8.encode('hi\n')),
    ));
    controller.handleMessage(SSH_Message_Channel_Request.exitStatus(
      recipientChannel: 1,
      exitStatus: 5,
    ));
    controller.handleMessage(SSH_Message_Channel_Close(recipientChannel: 1));

    final session = SSHSession(controller.channel);
    final out = await session.stdout.toList();
    await session.done;

    expect(utf8.decode(out.expand((e) => e).toList()), 'hi\n');
    expect(session.exitCode, 5);
  });
}
