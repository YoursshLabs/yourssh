// 16 AI chat sidebar (no external call: a fake key is stored in the in-memory secure storage).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'nav.dart';
import 'sections.dart';

const s = '16-ai-chat';

Future<void> runAi(JourneyContext c) async {
  final t = c.t;
  await navTo(t, 'Settings', wait: 900);
  await step(c.notes, 'ai key', () async {
    await scrollTo(t, find.text('AI providers').first, alignment: 0.02);
    await c.snap('$s/01-unconfigured', 'Settings > AI providers before any key is entered: the chat toggle is hidden in the terminal header until a provider is configured');
    await typeKey(t, 'ai-key-anthropic', 'sk-ant-demo-not-a-real-key-0000');
    await sleepPump(t, 300);
    await c.snap('$s/02-key-obscured', 'API key typed into the Anthropic field: the value is obscured');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await sleepPump(t, 800);
    await c.snap('$s/03-configured', 'Key saved: Anthropic shows the Configured check');
  });
  await t.tap(find.textContaining('Demo Server · demo').first, warnIfMissed: false);
  await sleepPump(t, 800);
  await tapTooltip(t, 'Open AI Chat', wait: 900);
  await c.snap('$s/04-chat-open', 'AI chat sidebar open beside the terminal (empty conversation)');
  await step(c.notes, 'provider', () async {
    await tapKey(t, 'ai-chat-provider', wait: 600);
    await c.snap('$s/05-provider-menu', 'Provider selector (configured providers)');
    await pressEscape(t);
  });
  await step(c.notes, 'prompt', () async {
    await typeKey(t, 'ai-chat-input', 'List the 5 biggest files in /var/log\nand explain what each one is for');
    await sleepPump(t, 400);
    await c.snap('$s/06-multiline-prompt', 'A multi-line prompt (Shift+Enter inserts a newline). It is not sent: no external API is called');
    await typeKey(t, 'ai-chat-input', '');
  });
  await step(c.notes, 'close', () => tapTooltip(t, 'Close AI Chat', wait: 600));
}
