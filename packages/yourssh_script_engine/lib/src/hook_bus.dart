class TransformEvent {
  final String sessionId;
  final String data;
  const TransformEvent({required this.sessionId, required this.data});
  TransformEvent copyWith({String? data}) =>
      TransformEvent(sessionId: sessionId, data: data ?? this.data);
}

class ObserveEvent {
  final String sessionId;
  final Map<String, dynamic> payload;
  const ObserveEvent({required this.sessionId, required this.payload});
}

typedef TransformHandler = dynamic Function(TransformEvent event);
typedef ObserveHandler = void Function(ObserveEvent event);

class _HandlerEntry {
  final String pluginId;
  final TransformHandler? transformFn;
  final ObserveHandler? observeFn;
  const _HandlerEntry.transform(this.pluginId, this.transformFn)
      : observeFn = null;
  const _HandlerEntry.observe(this.pluginId, this.observeFn)
      : transformFn = null;
}

class HookBus {
  final _handlers = <String, List<_HandlerEntry>>{};

  void register(String event, String pluginId, TransformHandler handler) {
    _handlers.putIfAbsent(event, () => [])
        .add(_HandlerEntry.transform(pluginId, handler));
  }

  void registerObserver(String event, String pluginId, ObserveHandler handler) {
    _handlers.putIfAbsent(event, () => [])
        .add(_HandlerEntry.observe(pluginId, handler));
  }

  void unregisterAll(String pluginId) {
    for (final list in _handlers.values) {
      list.removeWhere((e) => e.pluginId == pluginId);
    }
  }

  String fireTransform(String event, TransformEvent initial) {
    final handlers = _handlers[event];
    if (handlers == null) return initial.data;
    var current = initial;
    for (final entry in handlers) {
      if (entry.transformFn == null) continue;
      try {
        final result = entry.transformFn!(current);
        if (result is String) current = current.copyWith(data: result);
      } catch (_) {}
    }
    return current.data;
  }

  String? fireInterceptable(String event, TransformEvent initial) {
    final handlers = _handlers[event];
    if (handlers == null) return initial.data;
    var current = initial;
    for (final entry in handlers) {
      if (entry.transformFn == null) continue;
      try {
        final result = entry.transformFn!(current);
        if (result == false) return null;
        if (result is String) current = current.copyWith(data: result);
      } catch (_) {}
    }
    return current.data;
  }

  void fireObserve(String event, ObserveEvent e) {
    final handlers = _handlers[event];
    if (handlers == null) return;
    for (final entry in handlers) {
      try {
        entry.observeFn?.call(e);
      } catch (_) {}
    }
  }
}
