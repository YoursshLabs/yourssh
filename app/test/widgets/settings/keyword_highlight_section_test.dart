import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/keyword_highlight_rule.dart';
import 'package:yourssh/widgets/settings/keyword_highlight_section.dart';
import 'package:yourssh_ui/yourssh_ui.dart';

import 'settings_harness.dart';

/// Settings → Keyword highlighting: toggles, add/edit/delete and colours.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(mockPrefs);

  Finder byKey(String k) => find.byKey(ValueKey(k));

  testWidgets('default rules listed; master and rule switches persist', (
    tester,
  ) async {
    final h = SettingsHarness();
    await h.pump(tester, const KeywordHighlightSection());

    expect(find.text('Keyword highlighting'), findsOneWidget);
    expect(find.text('Enable keyword highlighting'), findsOneWidget);
    expect(find.text('Error'), findsOneWidget);
    expect(find.text('literal  ·  error'), findsOneWidget);
    expect(find.byTooltip('Edit rule'), findsWidgets);
    expect(find.byTooltip('Delete rule'), findsWidgets);

    await tapSwitch(tester, const ValueKey('settings-keyword-enable'));
    expect(h.settings.keywordHighlightingEnabled, isFalse);

    expect(h.settings.keywordHighlightRules.first.enabled, isTrue);
    await tapSwitch(tester, const ValueKey('keyword-rule-switch-0'));
    expect(h.settings.keywordHighlightRules.first.enabled, isFalse);
  });

  testWidgets('Add rule: needs a colour, then saves a new rule', (
    tester,
  ) async {
    final h = SettingsHarness();
    await h.pump(tester, const KeywordHighlightSection());
    final before = h.settings.keywordHighlightRules.length;

    await tester.tap(byKey('keyword-add-rule'));
    await tester.pumpAndSettle();
    expect(find.text('Add rule'), findsWidgets);

    await tester.enterText(byKey('keyword-rule-label'), 'Deploy');
    await tester.enterText(byKey('keyword-rule-pattern'), 'deploy');
    await tester.pumpAndSettle();
    expect(find.text('Choose at least one color.'), findsOneWidget);
    final save = tester.widget<FButton>(
      find.ancestor(of: find.text('Save'), matching: find.byType(FButton)),
    );
    expect(save.onPress, isNull, reason: 'no colour yet');

    await tester.tap(byKey('keyword-rule-fg'));
    await tester.pumpAndSettle();
    expect(find.text('Pick color'), findsOneWidget);
    await tester.tap(byKey('keyword-color-0'));
    await tester.pumpAndSettle();
    expect(find.text('Choose at least one color.'), findsNothing);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final rules = h.settings.keywordHighlightRules;
    expect(rules, hasLength(before + 1));
    expect(rules.last.label, 'Deploy');
    expect(rules.last.pattern, 'deploy');
    expect(rules.last.isRegex, isFalse);
    expect(rules.last.foreground, isNotNull);
    expect(rules.last.background, isNull);
    expect(rules.last.enabled, isTrue);
  });

  testWidgets('regex pattern errors block Save', (tester) async {
    final h = SettingsHarness();
    await h.pump(tester, const KeywordHighlightSection());

    await tester.tap(byKey('keyword-add-rule'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('keyword-rule-regex'));
    await tester.pumpAndSettle();
    await tester.enterText(byKey('keyword-rule-label'), 'Bad');
    await tester.enterText(byKey('keyword-rule-pattern'), '(unclosed');
    await tester.pumpAndSettle();
    await tester.tap(byKey('keyword-rule-bg'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('keyword-color-1'));
    await tester.pumpAndSettle();

    final save = tester.widget<FButton>(
      find.ancestor(of: find.text('Save'), matching: find.byType(FButton)),
    );
    expect(save.onPress, isNull);
  });

  testWidgets('edit keeps the rule id; delete removes it', (tester) async {
    final h = SettingsHarness();
    await h.pump(tester, const KeywordHighlightSection());
    final first = h.settings.keywordHighlightRules.first;

    await tester.tap(byKey('keyword-rule-edit-0'));
    await tester.pumpAndSettle();
    expect(find.text('Edit rule'), findsWidgets);
    await tester.enterText(byKey('keyword-rule-label'), 'Errors');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(h.settings.keywordHighlightRules.first.label, 'Errors');
    expect(h.settings.keywordHighlightRules.first.id, first.id);

    final count = h.settings.keywordHighlightRules.length;
    await tester.tap(byKey('keyword-rule-delete-0'));
    await tester.pumpAndSettle();
    expect(h.settings.keywordHighlightRules, hasLength(count - 1));
    expect(
      h.settings.keywordHighlightRules.any((r) => r.id == first.id),
      isFalse,
    );
  });

  testWidgets('the colour picker can clear a colour', (tester) async {
    final h = SettingsHarness();
    await h.pump(tester, const KeywordHighlightSection());

    // Rule 0 ("Error") has a background only.
    await tester.tap(byKey('keyword-rule-edit-0'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('keyword-rule-fg'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('keyword-color-0'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('keyword-rule-bg'));
    await tester.pumpAndSettle();
    await tester.tap(byKey('keyword-color-none'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final rule = h.settings.keywordHighlightRules.first;
    expect(rule.background, isNull);
    expect(rule.foreground, isNotNull);
  });

  testWidgets('at the rule cap, Add rule gives way to a notice', (
    tester,
  ) async {
    final h = SettingsHarness();
    await h.pump(tester, const KeywordHighlightSection());
    await tester.runAsync(
      () => h.settings.save(
        keywordHighlightRules: [
          for (var i = 0; i < kMaxKeywordHighlightRules; i++)
            AppKeywordHighlightRule(
              label: 'r$i',
              pattern: 'p$i',
              isRegex: false,
              caseSensitive: false,
              enabled: true,
              foreground: const Color(0xFFFFFFFF),
              background: null,
            ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(byKey('keyword-add-rule'), findsNothing);
    expect(
      find.text('Maximum $kMaxKeywordHighlightRules rules reached.'),
      findsOneWidget,
    );
  });
}
