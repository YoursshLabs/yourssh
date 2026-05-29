// app/lib/widgets/code_editor_screen.dart
// Placeholder — will be replaced in Task 23 with full Monaco implementation
import 'package:flutter/material.dart';
import '../models/sftp_entry.dart';
import '../models/ssh_session.dart';

class CodeEditorScreen extends StatelessWidget {
  final SshSession session;
  final SftpEntry entry;

  const CodeEditorScreen({
    super.key,
    required this.session,
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(entry.name)),
      body: const Center(child: Text('Editor coming soon')),
    );
  }
}
