class PathPlan {
  final String dir; // remote directory to list
  final String prefix; // filter applied to entries
  const PathPlan({required this.dir, required this.prefix});
}

const _pathCommands = {
  'cd', 'ls', 'cat', 'less', 'more', 'tail', 'head',
  'cp', 'mv', 'rm', 'vim', 'vi', 'nano', 'source', 'touch', 'mkdir',
};

/// Decide whether the current input wants path completion, and if so which
/// remote dir to list and what prefix to filter by. Returns null when the
/// input isn't a path context or a relative path can't be resolved (no cwd).
PathPlan? planPathCompletion(String input, String? cwd) {
  if (input.isEmpty) return null;
  final parts = input.split(' ');
  if (parts.length == 1) return null; // still typing the command word
  final first = parts.first;
  final token = parts.last; // arg token (may be '')
  // '~' (home) can't be resolved without the remote $HOME; skip rather than
  // listing a bogus '$cwd/~'. Falls back to history suggestions.
  if (token.startsWith('~')) return null;
  final isPathCmd = _pathCommands.contains(first);
  final looksPath =
      token.contains('/') || token.startsWith('.') || token.startsWith('~');
  if (!isPathCmd && !looksPath) return null;

  final slash = token.lastIndexOf('/');
  final dirPart = slash < 0 ? '' : token.substring(0, slash + 1);
  final prefix = slash < 0 ? token : token.substring(slash + 1);

  String dir;
  if (dirPart.startsWith('/')) {
    dir = _trimSlash(dirPart);
  } else {
    if (cwd == null) return null;
    dir = dirPart.isEmpty ? cwd : '$cwd/${_trimSlash(dirPart)}';
  }
  return PathPlan(dir: dir.isEmpty ? '/' : dir, prefix: prefix);
}

String _trimSlash(String s) =>
    s.length > 1 && s.endsWith('/') ? s.substring(0, s.length - 1) : s;

/// Build full-command suggestions by completing the path token with each
/// matching directory entry (entries may carry a trailing '/').
List<String> mergePathSuggestions(
    String input, PathPlan plan, List<String> entries) {
  // The prefix is always a suffix of the input (the trailing chars of the last
  // token), so the head is simply the input minus that prefix — independent of
  // any '/' in earlier arguments.
  final head = input.substring(0, input.length - plan.prefix.length);
  return entries
      .where((e) => e.startsWith(plan.prefix))
      .map((e) => '$head$e')
      .take(8)
      .toList();
}
