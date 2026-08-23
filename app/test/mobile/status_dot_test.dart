import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/theme/mobile_theme.dart';
import 'package:yourssh/mobile/widgets/status_dot.dart';

void main() {
  test('statusColor maps each state', () {
    expect(statusColor(HostConnState.connected), MobileColors.green);
    expect(statusColor(HostConnState.connecting), MobileColors.accent);
    expect(statusColor(HostConnState.offline), MobileColors.textFaint);
  });
}
