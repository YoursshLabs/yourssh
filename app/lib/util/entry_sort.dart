/// Sort columns of the SFTP file listings (`YsSort.column` ids).
abstract final class EntrySortColumn {
  static const name = 'name';
  static const modified = 'modified';
  static const size = 'size';
  static const kind = 'kind';
}

/// Comparator for a file listing sorted by [column]: folders always come
/// first, then [column] in the given direction; ties fall back to the name
/// (case-insensitive, then exact) so the order is total and stable across
/// reloads. Name ascending is the listings' historical order (`sortKey`).
Comparator<T> entryComparator<T>(
  String column, {
  required bool ascending,
  required bool Function(T) isDirectory,
  required String Function(T) name,
  required int Function(T) size,
  required DateTime Function(T) modified,
  required String Function(T) kind,
}) {
  int byName(T a, T b) {
    final c = name(a).toLowerCase().compareTo(name(b).toLowerCase());
    return c != 0 ? c : name(a).compareTo(name(b));
  }

  return (a, b) {
    final aDir = isDirectory(a);
    if (aDir != isDirectory(b)) return aDir ? -1 : 1;
    final c = switch (column) {
      EntrySortColumn.size => size(a).compareTo(size(b)),
      EntrySortColumn.modified => modified(a).compareTo(modified(b)),
      EntrySortColumn.kind => kind(a).compareTo(kind(b)),
      _ => byName(a, b),
    };
    if (c != 0) return ascending ? c : -c;
    return byName(a, b);
  };
}

/// The selection after a `YsFileTable.onSelect` gesture on [entry] in
/// [visible] (display order), given the current [selected] keys and the
/// range [anchor]: plain replaces the selection, [additive] toggles [entry],
/// [range] selects the run between the anchor and [entry] (added to the
/// selection when [additive] too). Returns the new selection and anchor.
(Set<K>, K?) applyTableSelection<E, K>({
  required List<E> visible,
  required K Function(E) keyOf,
  required Set<K> selected,
  required K? anchor,
  required E entry,
  required bool additive,
  required bool range,
}) {
  final key = keyOf(entry);
  if (range) {
    final from = anchor == null
        ? -1
        : visible.indexWhere((e) => keyOf(e) == anchor);
    final to = visible.indexWhere((e) => keyOf(e) == key);
    if (from < 0 || to < 0) return ({key}, key);
    final run = {
      for (var i = from < to ? from : to; i <= (from < to ? to : from); i++)
        keyOf(visible[i]),
    };
    return (additive ? {...selected, ...run} : run, anchor);
  }
  if (additive) {
    final next = {...selected};
    if (!next.remove(key)) next.add(key);
    return (next, key);
  }
  return ({key}, key);
}
