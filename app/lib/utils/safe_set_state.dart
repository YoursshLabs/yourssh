import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// `setState` for callbacks that can fire from another widget's
/// initState/dispose (a shared notifier, a provider). Those run inside the
/// build/finalize phase, where setState throws "widget tree was locked";
/// in that phase the rebuild is deferred to the end of the frame.
extension SafeSetState on State {
  // ignore: invalid_use_of_protected_member
  void setStateSafely() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // ignore: invalid_use_of_protected_member
        if (mounted) setState(() {});
      });
      return;
    }
    // ignore: invalid_use_of_protected_member
    setState(() {});
  }
}
