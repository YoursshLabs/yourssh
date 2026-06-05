// app/test/providers/terminal_layout_provider_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/providers/terminal_layout_provider.dart';

void main() {
  test('default layout is single', () {
    final p = TerminalLayoutProvider();
    expect(p.layout, SplitLayout.single);
  });

  test('setLayout updates layout', () {
    final p = TerminalLayoutProvider();
    p.setLayout(SplitLayout.horizontal);
    expect(p.layout, SplitLayout.horizontal);
  });

  test('broadcastEnabled defaults to false', () {
    final p = TerminalLayoutProvider();
    expect(p.broadcastEnabled, false);
  });

  test('toggleBroadcast flips flag', () {
    final p = TerminalLayoutProvider();
    p.toggleBroadcast();
    expect(p.broadcastEnabled, true);
    p.toggleBroadcast();
    expect(p.broadcastEnabled, false);
  });

  test('paneCount matches layout', () {
    final p = TerminalLayoutProvider();
    expect(p.paneCount, 1);
    p.setLayout(SplitLayout.horizontal);
    expect(p.paneCount, 2);
    p.setLayout(SplitLayout.quad);
    expect(p.paneCount, 4);
  });

  test('setLayout notifies listeners', () {
    final p = TerminalLayoutProvider();
    var notificationCount = 0;
    p.addListener(() => notificationCount++);
    p.setLayout(SplitLayout.horizontal);
    expect(notificationCount, 1);
    p.setLayout(SplitLayout.vertical);
    expect(notificationCount, 2);
  });

  test('toggleBroadcast notifies listeners', () {
    final p = TerminalLayoutProvider();
    var notificationCount = 0;
    p.addListener(() => notificationCount++);
    p.toggleBroadcast();
    expect(notificationCount, 1);
  });

  test('snippetsPanelVisible defaults to false', () {
    final p = TerminalLayoutProvider();
    expect(p.snippetsPanelVisible, false);
  });

  test('toggleSnippetsPanel flips visibility', () {
    final p = TerminalLayoutProvider();
    p.toggleSnippetsPanel();
    expect(p.snippetsPanelVisible, true);
    p.toggleSnippetsPanel();
    expect(p.snippetsPanelVisible, false);
  });

  test('toggleSnippetsPanel notifies listeners', () {
    final p = TerminalLayoutProvider();
    var notificationCount = 0;
    p.addListener(() => notificationCount++);
    p.toggleSnippetsPanel();
    expect(notificationCount, 1);
  });

  test('sidePanel defaults to none', () {
    final p = TerminalLayoutProvider();
    expect(p.sidePanel, SidePanel.none);
    expect(p.configPanelVisible, false);
  });

  test('toggleSidePanel opens and closes the same panel', () {
    final p = TerminalLayoutProvider();
    p.toggleSidePanel(SidePanel.terminalConfig);
    expect(p.configPanelVisible, true);
    p.toggleSidePanel(SidePanel.terminalConfig);
    expect(p.configPanelVisible, false);
    expect(p.sidePanel, SidePanel.none);
  });

  test('opening config panel closes snippets panel', () {
    final p = TerminalLayoutProvider();
    p.toggleSnippetsPanel();
    expect(p.snippetsPanelVisible, true);
    p.toggleSidePanel(SidePanel.terminalConfig);
    expect(p.configPanelVisible, true);
    expect(p.snippetsPanelVisible, false);
  });

  test('opening snippets panel closes config panel', () {
    final p = TerminalLayoutProvider();
    p.toggleSidePanel(SidePanel.terminalConfig);
    p.toggleSnippetsPanel();
    expect(p.snippetsPanelVisible, true);
    expect(p.configPanelVisible, false);
  });

  test('toggleSidePanel notifies listeners', () {
    final p = TerminalLayoutProvider();
    var notificationCount = 0;
    p.addListener(() => notificationCount++);
    p.toggleSidePanel(SidePanel.terminalConfig);
    expect(notificationCount, 1);
  });
}
