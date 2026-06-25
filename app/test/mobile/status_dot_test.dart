import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh/mobile/widgets/status_dot.dart';

void main() {
  test('statusColor maps each state', () {
    expect(statusColor(HostConnState.connected), AppColors.accent);
    expect(statusColor(HostConnState.connecting), AppColors.orange);
    expect(statusColor(HostConnState.offline), AppColors.textTertiary);
  });
}
