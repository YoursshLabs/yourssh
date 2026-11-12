import 'dart:convert';
import 'dart:io';

/// Turns the value returned by `runJavaScriptReturningResult` into the plain
/// string the page produced.
///
/// On Android webview_flutter returns the raw `evaluateJavascript` result,
/// which is JSON-encoded, so a JS string `abc\n` arrives as `"abc\\n"` with
/// surrounding quotes. iOS/macOS return the string unquoted, so decoding there
/// would corrupt a file that genuinely starts and ends with `"`.
String decodeWebViewString(Object result, {bool? jsonEncoded}) {
  final raw = result.toString();
  if (!(jsonEncoded ?? Platform.isAndroid)) return raw;
  if (raw.length < 2 || !raw.startsWith('"') || !raw.endsWith('"')) return raw;
  try {
    final decoded = jsonDecode(raw);
    return decoded is String ? decoded : raw;
  } on FormatException {
    return raw;
  }
}
