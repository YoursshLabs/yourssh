import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/mobile/widgets/tag_chip.dart';
import 'package:yourssh/mobile/widgets/section_header.dart';
import 'package:yourssh/mobile/widgets/mobile_card.dart';

void main() {
  testWidgets('TagChip renders label', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: TagChip(label: 'prod'))));
    expect(find.text('prod'), findsOneWidget);
  });

  testWidgets('SectionHeader uppercases the title', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: SectionHeader('security'))));
    expect(find.text('SECURITY'), findsOneWidget);
  });

  testWidgets('MobileCard fires onTap', (t) async {
    var tapped = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MobileCard(onTap: () => tapped = true, child: const Text('x')),
      ),
    ));
    await t.tap(find.text('x'));
    expect(tapped, isTrue);
  });
}
