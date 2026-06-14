import 'dart:convert';

/// Maximum decoded clipboard payload accepted from an OSC 52 write (1 MiB).
const int kOsc52MaxBytes = 1 << 20;

/// Result of parsing an OSC 52 argument list.
sealed class Osc52Result {
  const Osc52Result();
}

/// A clipboard-write request carrying the decoded [text].
class Osc52Write extends Osc52Result {
  final String text;
  const Osc52Write(this.text);
}

/// Not a write we honor: a read query (`?`), invalid base64, an oversized
/// payload, or a malformed argument list.
class Osc52Ignored extends Osc52Result {
  const Osc52Ignored();
}

class Osc52Clipboard {
  /// Parses the OSC 52 argument tail (everything after the `52` code).
  ///
  /// For `OSC 52 ; c ; <base64>` the caller hands us `['c', '<base64>']`.
  /// The selection target (first element) is ignored — desktop has a single
  /// system clipboard. Returns [Osc52Write] only for a valid, in-cap payload;
  /// every other case is [Osc52Ignored] (fail-soft — never throws).
  static Osc52Result parse(List<String> args) {
    if (args.length < 2) return const Osc52Ignored();
    final data = args.last;
    if (data == '?') return const Osc52Ignored(); // read query — never honored
    final List<int> bytes;
    try {
      bytes = base64.decode(base64.normalize(data));
    } on FormatException {
      return const Osc52Ignored();
    }
    if (bytes.length > kOsc52MaxBytes) return const Osc52Ignored();
    return Osc52Write(utf8.decode(bytes, allowMalformed: true));
  }
}
