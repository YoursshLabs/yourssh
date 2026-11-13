// 10 recordings: stop the recording started in section 03, library, player.
import 'package:yourssh_ui/yourssh_ui.dart' show FLucideIcons;
import 'nav.dart';
import 'sections.dart';
import 'package:flutter_test/flutter_test.dart';

const s = '10-recordings';

Future<void> runRecordings(JourneyContext c) async {
  final t = c.t;
  await step(c.notes, 'stop recording', () async {
    final tab = find.textContaining('Demo Server · demo');
    await t.tap(tab.first, warnIfMissed: false);
    await sleepPump(t, 700);
    await tapTooltip(t, 'Stop recording', wait: 900);
    await c.snap('$s/01-recording-stopped', 'Recording stopped: REC button back to idle');
  });
  await navTo(t, 'Recordings');
  await sleepPump(t, 600);
  await c.snap('$s/02-library', 'Recording library: one asciicast session with host, date, duration, size');
  await step(c.notes, 'player', () async {
    await tapTooltip(t, 'Play recording', wait: 1500);
    await c.snap('$s/03-player', 'Recording player opened (paused at 00:00): timeline, play button, speed control');
    await t.tap(find.byIcon(FLucideIcons.play).last, warnIfMissed: false);
    await sleepPump(t, 2800);
    await c.snap('$s/03b-player-playing', 'Recording playing: the session replays in the terminal view');
    await sleepPump(t, 2500);
    await tapTooltip(t, 'Close player', wait: 600);
  });
  await step(c.notes, 'delete', () async {
    await tapTooltip(t, 'Delete', wait: 700);
    await c.snap('$s/04-delete-confirm', 'Delete recording confirmation');
    await tapText(t, 'Cancel', wait: 500);
  });
}
