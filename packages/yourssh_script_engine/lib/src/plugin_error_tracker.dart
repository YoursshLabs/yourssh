class PluginErrorTracker {
  final String pluginId;
  int _count = 0;

  static const int _warnThreshold = 5;
  static const int _disableThreshold = 10;

  PluginErrorTracker(this.pluginId);

  /// Records a failure. A timeout is heavier than an ordinary error because a
  /// runaway hook freezes the UI isolate while it runs.
  void recordError({int weight = 1}) => _count += weight;

  /// Weight of one execution timeout.
  static const int timeoutWeight = 5;

  void reset() => _count = 0;

  bool get shouldWarn => _count >= _warnThreshold;

  bool get isDisabled => _count >= _disableThreshold;

  int get errorCount => _count;
}
