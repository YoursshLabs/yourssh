// app/test/services/app_discovery_service_linux_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/app_discovery_service.dart';

void main() {
  late Directory fixtureDir;

  setUpAll(() {
    fixtureDir = Directory('test/fixtures/applications');
  });

  test('parseDesktopFiles returns apps matching the MIME type', () async {
    final apps = await AppDiscoveryService.parseDesktopFiles(
      files: fixtureDir.listSync().whereType<File>().toList(),
      mimeType: 'text/plain',
      defaultDesktopFile: 'gedit.desktop',
    );
    expect(apps.map((a) => a.name), contains('Text Editor'));
    expect(apps.map((a) => a.name), isNot(contains('Image Viewer')));
    final gedit = apps.firstWhere((a) => a.name == 'Text Editor');
    expect(gedit.isDefault, isTrue);
  });

  test('parseDesktopFiles strips Exec placeholders', () async {
    final apps = await AppDiscoveryService.parseDesktopFiles(
      files: fixtureDir.listSync().whereType<File>().toList(),
      mimeType: 'text/plain',
      defaultDesktopFile: '',
    );
    final gedit = apps.firstWhere((a) => a.name == 'Text Editor');
    expect(gedit.executablePath, 'gedit');
    expect(gedit.executablePath, isNot(contains('%')));
  });

  test('parseDesktopFiles returns empty list when no MIME match', () async {
    final apps = await AppDiscoveryService.parseDesktopFiles(
      files: fixtureDir.listSync().whereType<File>().toList(),
      mimeType: 'application/pdf',
      defaultDesktopFile: '',
    );
    expect(apps, isEmpty);
  });

  test('%% in Exec is preserved as literal % and does not strip app name', () async {
    final apps = await AppDiscoveryService.parseDesktopFiles(
      files: fixtureDir.listSync().whereType<File>().toList(),
      mimeType: 'text/plain',
      defaultDesktopFile: '',
    );
    final vim = apps.firstWhere((a) => a.name.contains('Vim'));
    expect(vim.executablePath, 'vim');
    expect(vim.executablePath, isNot(contains('%')));
  });

  test('parseDesktopFiles ignores malformed desktop files gracefully', () async {
    final tmp = File('${fixtureDir.path}/broken.desktop')
      ..writeAsStringSync('not valid content at all');
    addTearDown(tmp.deleteSync);

    final apps = await AppDiscoveryService.parseDesktopFiles(
      files: fixtureDir.listSync().whereType<File>().toList(),
      mimeType: 'text/plain',
      defaultDesktopFile: '',
    );
    expect(apps.map((a) => a.name), contains('Text Editor'));
  });
}
