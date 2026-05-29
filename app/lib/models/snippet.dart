import 'package:uuid/uuid.dart';

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
