import 'package:yourssh_cli/yourssh_cli.dart' show sanitize;

import '../../models/app_notification.dart';

/// Longest link shown in the bell title.
const int _maxShown = 120;

/// Bell entry for a `yourssh://` open the app refused (unknown host,
/// unsupported shape). The link comes from a web page or another app, so
/// control and bidi-override characters are removed before display; the
/// same link (any case) refused again replaces the earlier entry.
AppNotification linkRefusedNotification(String url, String reason) {
  var shown = _clean(url);
  if (shown.length > _maxShown) shown = '${shown.substring(0, _maxShown)}…';
  return AppNotification(
    type: AppNotificationType.linkRefused,
    title: 'Link refused: $shown',
    body: _clean(reason),
    dedupeKey: 'link-refused:${shown.toLowerCase()}',
  );
}

/// C0/C1 controls (via [sanitize]) plus the Unicode bidi controls that can
/// make a link read differently from what it is.
String _clean(String s) => sanitize(s).replaceAll(
    RegExp('[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]'), '');
