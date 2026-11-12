import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/ssh_service.dart';
import 'package:yourssh/services/storage_service.dart';

/// Records every command and answers from a stub. Shared by service tests.
class RecordingSsh extends SshService {
  RecordingSsh() : super(StorageService());

  final List<String> execCmds = [];
  final List<String> streamCmds = [];
  ({String stdout, String stderr, int exitCode}) Function(String cmd)? execStub;
  Stream<String> Function(String cmd)? streamStub;

  @override
  Future<({String stdout, String stderr, int exitCode})> exec(
      Host host, String cmd, {String? auditSource}) async {
    execCmds.add(cmd);
    return execStub?.call(cmd) ?? (stdout: '', stderr: '', exitCode: 0);
  }

  @override
  Stream<String> execStream(Host host, String cmd, {String? auditSource}) {
    streamCmds.add(cmd);
    return streamStub?.call(cmd) ?? const Stream.empty();
  }
}
