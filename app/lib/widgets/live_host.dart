import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../models/host.dart';
import '../providers/host_provider.dart';

/// The current stored version of [snapshot] (a session's `host` goes stale
/// after an edit): looked up by id in [HostProvider], falling back to the
/// snapshot when the provider is absent or the host was deleted. A narrow
/// `select`, so the caller rebuilds only when THAT host is replaced, never on
/// terminal output or edits to other hosts.
Host selectLiveHost(BuildContext context, Host snapshot) {
  try {
    return context.select<HostProvider, Host?>((p) => p.byId(snapshot.id)) ??
        snapshot;
  } on ProviderNotFoundException {
    return snapshot;
  }
}
