// app/test/models/app_option_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/app_option.dart';

void main() {
  test('AppOption stores fields correctly', () {
    const opt = AppOption(
      name: 'VS Code',
      executablePath: '/Applications/Visual Studio Code.app',
      iconPath: '/Applications/Visual Studio Code.app/Contents/Resources/Code.icns',
      isDefault: true,
    );
    expect(opt.name, 'VS Code');
    expect(opt.executablePath, '/Applications/Visual Studio Code.app');
    expect(opt.iconPath,
        '/Applications/Visual Studio Code.app/Contents/Resources/Code.icns');
    expect(opt.isDefault, isTrue);
  });

  test('AppOption with null iconPath', () {
    const opt = AppOption(
      name: 'gedit',
      executablePath: '/usr/bin/gedit',
      isDefault: false,
    );
    expect(opt.iconPath, isNull);
  });
}
