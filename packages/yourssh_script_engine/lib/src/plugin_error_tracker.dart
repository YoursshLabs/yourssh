class PluginErrorTracker {
  final String pluginId;
  int _count = 0;

  static const int _warnThreshold = 5;
  static const int _disableThreshold = 10;

  PluginErrorTracker(this.pluginId);

  void recordError() => _count++;

  void reset() => _count = 0;

  bool get shouldWarn => _count >= _warnThreshold;

  bool get isDisabled => _count >= _disableThreshold;

  int get errorCount => _count;
}
