import 'package:uuid/uuid.dart';

/// Case-insensitive snippet search over label, command, and tag — the one
/// filter used by both the snippets screen and the terminal side panel.
List<Snippet> filterSnippets(List<Snippet> snippets, String query) {
  if (query.isEmpty) return snippets;
  final q = query.toLowerCase();
  return snippets
      .where((s) =>
          s.label.toLowerCase().contains(q) ||
          s.command.toLowerCase().contains(q) ||
          s.tag.toLowerCase().contains(q))
      .toList();
}

class Snippet {
  final String id;
  String label;
  String command;
  String description;
  String tag;

  Snippet({
    String? id,
    required this.label,
    required this.command,
    this.description = '',
    this.tag = '',
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'command': command,
        'description': description,
        'tag': tag,
      };

  factory Snippet.fromJson(Map<String, dynamic> json) => Snippet(
        id: json['id'],
        label: json['label'],
        command: json['command'],
        description: json['description'] ?? '',
        tag: json['tag'] ?? '',
      );
}
