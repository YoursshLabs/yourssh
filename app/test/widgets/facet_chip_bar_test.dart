import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/widgets/hosts_dashboard.dart';

void main() {
  testWidgets('renders a chip per facet and reports taps', (tester) async {
    String? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: facetChipBarForTest(
          facets: const ['env:prod', 'role:db'],
          query: 'env:prod',
          onToggle: (f) => tapped = f,
        ),
      ),
    ));

    expect(find.text('env:prod'), findsOneWidget);
    expect(find.text('role:db'), findsOneWidget);

    await tester.tap(find.text('role:db'));
    expect(tapped, 'role:db');
  });
}
