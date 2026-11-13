import 'package:dartssh2/dartssh2.dart' show SftpStatusError;

/// Turns an SFTP failure into a sentence the UI can show, instead of
/// `SftpStatusError: Failure(code 4)`. [name] is the file/folder the
/// operation was about.
String describeSftpError(Object error, {required String name}) {
  if (error is SftpStatusError) {
    return switch (error.code) {
      2 => '"$name" no longer exists.',
      3 => 'Permission denied for "$name".',
      4 => 'The server could not complete the operation on "$name" '
          '(it may already exist, or the path is not allowed).',
      6 || 7 => 'The connection to the server was lost.',
      8 => 'The server does not support this operation.',
      _ => error.message.isEmpty
          ? 'The server reported an error (code ${error.code}).'
          : error.message,
    };
  }
  return error.toString();
}

/// "<name> already exists" when [name] is in the current listing, else null.
String? existsMessage(Iterable<String> names, String name) =>
    names.contains(name) ? '"$name" already exists.' : null;
