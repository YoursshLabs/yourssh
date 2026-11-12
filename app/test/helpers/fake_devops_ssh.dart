import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/models/ssh_session.dart';
import 'package:yourssh/providers/session_provider.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';
import 'package:yourssh/services/tab_metadata_service.dart';

import 'ys_test_app.dart';

/// SshService whose `exec` records commands and answers via [reply].
class FakeDevopsSsh extends SshService {
  FakeDevopsSsh({this.reply}) : super(StorageService());

  final List<String> cmds = [];
  ({String stdout, String stderr, int exitCode}) Function(String cmd)? reply;

  @override
  Future<({String stdout, String stderr, int exitCode})> exec(
    Host host,
    String cmd, {
    String? auditSource,
  }) async {
    cmds.add(cmd);
    return reply?.call(cmd) ?? (stdout: '', stderr: '', exitCode: 0);
  }
}

/// Wraps [child] in `ysTestApp` with an SshService and a SessionProvider.
Widget devopsHarness(
  Widget child,
  FakeDevopsSsh fake, {
  bool withSession = true,
  String username = 'u',
}) {
  final sessions = SessionProvider(fake, TabMetadataService());
  if (withSession) {
    sessions.sessions.add(SshSession(
      host: Host(label: 'h', host: 'srv', port: 22, username: username),
      status: SessionStatus.connected,
    ));
  }
  return MultiProvider(
    providers: [
      Provider<SshService>.value(value: fake),
      ChangeNotifierProvider.value(value: sessions),
    ],
    child: ysTestApp(child),
  );
}
