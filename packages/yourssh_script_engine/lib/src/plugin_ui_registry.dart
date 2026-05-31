import 'package:flutter/foundation.dart';

class StatusBarItem {
  final String id;
  final String pluginId;
  String label;
  String? tooltip;
  VoidCallback? onClick;

  StatusBarItem({
    required this.id,
    required this.pluginId,
    required this.label,
    this.tooltip,
    this.onClick,
  });
}

class CommandEntry {
  final String commandId;
  final String pluginId;
  final String label;
  final String? keybinding;
  final VoidCallback handler;

  const CommandEntry({
    required this.commandId,
    required this.pluginId,
    required this.label,
    this.keybinding,
    required this.handler,
  });
}

class ContextMenuItem {
  final String id;
  final String pluginId;
  final String label;
  final String when;
  final void Function(Map<String, dynamic> ctx) handler;

  const ContextMenuItem({
    required this.id,
    required this.pluginId,
    required this.label,
    required this.when,
    required this.handler,
  });
}

class PluginPanelEntry {
  final String pluginId;
  final String title;
  final String icon;
  final String webviewEntry;
  final Future<String?> Function(Map<String, dynamic> msg) onMessage;

  const PluginPanelEntry({
    required this.pluginId,
    required this.title,
    required this.icon,
    required this.webviewEntry,
    required this.onMessage,
  });
}

class PluginUiRegistry extends ChangeNotifier {
  final _statusBar = <String, StatusBarItem>{};
  final _commands = <String, CommandEntry>{};
  final _contextMenu = <String, ContextMenuItem>{};
  final _panels = <String, PluginPanelEntry>{};

  List<StatusBarItem> get statusBarItems => _statusBar.values.toList();
  List<CommandEntry> get commands => _commands.values.toList();
  List<ContextMenuItem> get contextMenuItems => _contextMenu.values.toList();
  List<PluginPanelEntry> get panels => _panels.values.toList();

  void addStatusBarItem(StatusBarItem item) {
    _statusBar[item.id] = item;
    notifyListeners();
  }

  void updateStatusBarItem(String id, {String? label, String? tooltip}) {
    final item = _statusBar[id];
    if (item == null) return;
    if (label != null) item.label = label;
    if (tooltip != null) item.tooltip = tooltip;
    notifyListeners();
  }

  void removeStatusBarItem(String id) {
    _statusBar.remove(id);
    notifyListeners();
  }

  void addCommand(CommandEntry entry) {
    _commands[entry.commandId] = entry;
    notifyListeners();
  }

  void addContextMenuItem(ContextMenuItem item) {
    _contextMenu[item.id] = item;
    notifyListeners();
  }

  void addPanel(PluginPanelEntry panel) {
    _panels[panel.pluginId] = panel;
    notifyListeners();
  }

  void clearPlugin(String pluginId) {
    _statusBar.removeWhere((_, v) => v.pluginId == pluginId);
    _commands.removeWhere((_, v) => v.pluginId == pluginId);
    _contextMenu.removeWhere((_, v) => v.pluginId == pluginId);
    _panels.remove(pluginId);
    notifyListeners();
  }
}
