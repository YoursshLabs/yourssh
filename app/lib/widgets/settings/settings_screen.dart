import 'package:flutter/material.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import 'ai_providers_section.dart';
import 'appearance_section.dart';
import 'audit_section.dart';
import 'connection_section.dart';
import 'hotkeys_section.dart';
import 'keyword_highlight_section.dart';
import 'monitoring_section.dart';
import 'recording_section.dart';
import 'security_section.dart';
import 'sync_section.dart';
import 'terminal_section.dart';
import 'updates_section.dart';

/// The Settings screen: one section per file in this folder. One column at
/// the window minimum; two columns once there is room, each column its own
/// focus traversal group so Tab finishes the left column first.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum _Section {
  connection,
  appearance,
  terminal,
  keywords,
  recording,
  monitoring,
  audit,
  security,
  sync,
  ai,
  keyboard,
  updates,
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Content width from which the sections split into two columns.
  static const _twoColumnWidth = 1040.0;

  // Left then right is the single-column order; the split keeps the two
  // columns about the same height with the default keyword rules.
  static const _left = [
    _Section.connection,
    _Section.appearance,
    _Section.terminal,
    _Section.keywords,
  ];
  static const _right = [
    _Section.recording,
    _Section.monitoring,
    _Section.audit,
    _Section.security,
    _Section.sync,
    _Section.ai,
    _Section.keyboard,
    _Section.updates,
  ];

  /// Global keys keep each section's state (typed sync fields, AI keys)
  /// when a resize moves it between the one- and two-column layouts.
  final _keys = {for (final s in _Section.values) s: GlobalKey()};

  Widget _build(_Section s) => KeyedSubtree(
    key: _keys[s],
    child: switch (s) {
      _Section.connection => const ConnectionSettingsSection(),
      _Section.appearance => const AppearanceSettingsSection(),
      _Section.terminal => const TerminalSettingsSection(),
      _Section.keywords => const KeywordHighlightSection(),
      _Section.recording => const RecordingSettingsSection(),
      _Section.monitoring => const MonitoringSettingsSection(),
      _Section.audit => const AuditSettingsSection(),
      _Section.security => const SecuritySettingsSection(),
      _Section.sync => const SyncSettingsSection(),
      _Section.ai => const AiProvidersSettingsSection(),
      _Section.keyboard => const HotkeysSettingsSection(),
      _Section.updates => const UpdatesSettingsSection(),
    },
  );

  Widget _column(List<_Section> sections) => FocusTraversalGroup(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: YsSpace.s5,
      children: [for (final s in sections) _build(s)],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: YsColors.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const padding = YsSpace.s5;
          final twoColumns =
              constraints.maxWidth - 2 * padding >= _twoColumnWidth;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Settings',
                  style: TextStyle(
                    color: YsColors.foreground,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: YsSpace.s4),
                if (twoColumns)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _column(_left)),
                      const SizedBox(width: YsSpace.s5),
                      Expanded(child: _column(_right)),
                    ],
                  )
                else
                  _column([..._left, ..._right]),
              ],
            ),
          );
        },
      ),
    );
  }
}
