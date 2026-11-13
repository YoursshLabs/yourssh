// Section registry + shared journey context.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yourssh/providers/session_provider.dart';

import 'isolation.dart';
import 'nav.dart';
import 's01_launch.dart';
import 's02_add_host.dart';
import 's03_connect.dart';
import 's04_keychain.dart';
import 's05_hosts.dart';
import 's06_dashboard.dart';
import 's07_sftp.dart';
import 's08_portfwd.dart';
import 's09_known_hosts.dart';
import 's10_recordings.dart';
import 's11_audit.dart';
import 's12_rdp.dart';
import 's13_vnc.dart';
import 's14_settings.dart';
import 's15_plugins.dart';
import 's16_ai.dart';
import 's17_devops.dart';
import 's18_webtools.dart';
import 's19_notifications.dart';
import 's20_small.dart';
import 'm_mobile.dart';

class JourneyContext {
  JourneyContext(this.t, this.shots, this.sandbox);
  final WidgetTester t;
  final Shots shots;
  final DocsSandbox sandbox;
  final List<String> failures = [];
  final List<String> notes = [];
  final List<String> flutterErrors = [];

  BuildContext get appContext => t.element(find.byType(Scaffold).first);
  T read<T>() => Provider.of<T>(appContext, listen: false);
  SessionProvider get sessions => read<SessionProvider>();

  Future<void> snap(String rel, String caption, {int settleMs = 250}) =>
      shots.snap(t, rel, caption, settleMs: settleMs);

  /// Closes dialogs / panels left over by a failed section.
  Future<void> recover() async {
    for (var i = 0; i < 3; i++) {
      await pressEscape(t);
    }
  }

  Future<void> writeIndex() async {
    final b = StringBuffer('# Docs screenshots index\n\n');
    String? last;
    for (final (path, cap) in shots.taken) {
      final sec = path.split('/').first;
      if (sec != last) {
        b.writeln('\n## $sec\n');
        last = sec;
      }
      b.writeln('- `$path` — $cap');
    }
    if (notes.isNotEmpty) {
      b.writeln('\n## Notes / skipped\n');
      for (final n in notes) {
        b.writeln('- $n');
      }
    }
    if (flutterErrors.isNotEmpty) {
      b.writeln('\n## Framework errors logged during the run\n');
      for (final f in flutterErrors.toSet()) {
        b.writeln('- $f');
      }
    }
    if (failures.isNotEmpty) {
      b.writeln('\n## Section failures\n');
      for (final f in failures) {
        b.writeln('- $f');
      }
    }
    await File('${shots.outDir}/INDEX.${isMobileMode ? 'mobile' : 'desktop'}.part.md').writeAsString(b.toString());
  }
}

class Section {
  const Section(this.id, this.name, this.run);
  final String id;
  final String name;
  final Future<void> Function(JourneyContext) run;
}

final List<Section> allSections = [
  if (isMobileMode) Section('M1', 'mobile', runMobile),
  if (!isMobileMode) ...desktopSections,
];

bool get isMobileMode => Platform.environment['DOCS_MODE'] == 'mobile';

final List<Section> desktopSections = [
  Section('01', 'first-launch', runFirstLaunch),
  Section('02', 'add-host', runAddHost),
  Section('03', 'first-connect', runFirstConnect),
  Section('04', 'keychain', runKeychain),
  Section('05', 'more-hosts', runMoreHosts),
  Section('06', 'dashboard', runDashboard),
  Section('07', 'sftp', runSftp),
  Section('08', 'port-forwarding', runPortForward),
  Section('09', 'known-hosts', runKnownHosts),
  Section('10', 'recordings', runRecordings),
  Section('11', 'audit-log', runAudit),
  Section('12', 'rdp', runRdp),
  Section('13', 'vnc', runVnc),
  Section('14', 'settings', runSettings),
  Section('15', 'plugins', runPlugins),
  Section('16', 'ai-chat', runAi),
  Section('17', 'devops', runDevops),
  Section('18', 'web-tools', runWebTools),
  Section('19', 'notifications', runNotifications),
  Section('20', 'small-window', runSmall),
];
