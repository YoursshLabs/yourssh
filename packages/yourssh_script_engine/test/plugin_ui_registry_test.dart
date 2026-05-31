import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh_script_engine/src/plugin_ui_registry.dart';

void main() {
  test('addStatusBarItem and retrieve', () {
    final reg = PluginUiRegistry();
    reg.addStatusBarItem(StatusBarItem(id: 'a', pluginId: 'p1', label: 'Lbl'));
    expect(reg.statusBarItems.length, 1);
    expect(reg.statusBarItems.first.label, 'Lbl');
  });

  test('updateStatusBarItem changes label', () {
    final reg = PluginUiRegistry();
    reg.addStatusBarItem(StatusBarItem(id: 'a', pluginId: 'p1', label: 'Old'));
    reg.updateStatusBarItem('a', label: 'New');
    expect(reg.statusBarItems.first.label, 'New');
  });

  test('removeStatusBarItem removes it', () {
    final reg = PluginUiRegistry();
    reg.addStatusBarItem(StatusBarItem(id: 'a', pluginId: 'p1', label: 'X'));
    reg.removeStatusBarItem('a');
    expect(reg.statusBarItems, isEmpty);
  });

  test('clearPlugin removes all contributions for that plugin', () {
    final reg = PluginUiRegistry();
    reg.addStatusBarItem(StatusBarItem(id: 'a', pluginId: 'p1', label: 'X'));
    reg.addStatusBarItem(StatusBarItem(id: 'b', pluginId: 'p2', label: 'Y'));
    reg.addCommand(CommandEntry(
        commandId: 'cmd1', pluginId: 'p1', label: 'Cmd', handler: () {}));
    reg.clearPlugin('p1');
    expect(reg.statusBarItems.length, 1);
    expect(reg.statusBarItems.first.pluginId, 'p2');
    expect(reg.commands, isEmpty);
  });

  test('notifyListeners called on mutation', () {
    final reg = PluginUiRegistry();
    int notifications = 0;
    reg.addListener(() => notifications++);
    reg.addStatusBarItem(StatusBarItem(id: 'a', pluginId: 'p1', label: 'X'));
    reg.removeStatusBarItem('a');
    expect(notifications, 2);
  });
}
