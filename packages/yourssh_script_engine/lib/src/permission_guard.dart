class PermissionDeniedException implements Exception {
  final String permission;
  final String pluginId;

  const PermissionDeniedException(this.pluginId, this.permission);

  @override
  String toString() =>
      'Plugin "$pluginId" does not have permission: $permission';
}

class PermissionGuard {
  final String pluginId;
  final Set<String> _granted;

  const PermissionGuard({
    required String pluginId,
    required Set<String> granted,
  })  : pluginId = pluginId,
        _granted = granted;

  void require(String permission) {
    if (!_granted.contains(permission)) {
      throw PermissionDeniedException(pluginId, permission);
    }
  }

  bool has(String permission) => _granted.contains(permission);
}
