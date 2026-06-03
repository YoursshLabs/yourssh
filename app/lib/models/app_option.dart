// app/lib/models/app_option.dart
class AppOption {
  const AppOption({
    required this.name,
    required this.executablePath,
    this.iconPath,
    required this.isDefault,
  });

  final String name;
  final String executablePath;
  final String? iconPath;
  final bool isDefault;
}
