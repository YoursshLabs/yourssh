// app/test/widgets/health_dot_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/session_health.dart';
import 'package:yourssh/theme/app_theme.dart';
import 'package:yourssh/widgets/health_dot.dart';

void main() {
  testWidgets('HealthDot paints the tone color', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: HealthDot(tone: BadgeTone.green)),
    ));
    final dot = tester.widget<Container>(find.byKey(const Key('health-dot')));
    final decoration = dot.decoration as BoxDecoration;
    expect(decoration.color, AppColors.success);
  });

  testWidgets('HealthDot uses red for the red tone', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: HealthDot(tone: BadgeTone.red)),
    ));
    final dot = tester.widget<Container>(find.byKey(const Key('health-dot')));
    expect((dot.decoration as BoxDecoration).color, AppColors.red);
  });
}
