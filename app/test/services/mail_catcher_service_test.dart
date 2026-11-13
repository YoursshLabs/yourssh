import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/models/host.dart';
import 'package:yourssh/services/mail_catcher_service.dart';

import '../helpers/fake_devops_ssh.dart';

// Fixtures follow the CPython `Lib/smtpd.py` DebuggingServer output
// (Python 3 prints bytes lines as their repr, the X-Peer line as plain text,
// and `b''` for the header/body separator) and the aiosmtpd `Debugging`
// handler (plain text). Neither module is installed locally, so these were
// built from the source formats rather than captured.
const _smtpdBytes = '''
---------- MESSAGE FOLLOWS ----------
b'Subject: Hello there'
b'From: alice@example.com'
b'To: bob@example.com'
X-Peer: 127.0.0.1
b''
b'line one'
b''
b'line three: caf\\xc3\\xa9 and it\\'s ok'
------------ END MESSAGE ------------
---------- MESSAGE FOLLOWS ----------
b'Subject: Second'
b'From: carol@example.com'
b'To: dave@example.com'
X-Peer: 127.0.0.1
b''
b'only line'
b''
------------ END MESSAGE ------------
''';

const _aiosmtpd = '''
---------- MESSAGE FOLLOWS ----------
Subject: Hello there
From: alice@example.com
To: bob@example.com
X-Peer: ('127.0.0.1', 51234)

line one

line three
------------ END MESSAGE ------------
---------- MESSAGE FOLLOWS ----------
Subject: Second
From: carol@example.com
To: dave@example.com
X-Peer: ('127.0.0.1', 51235)

only line
------------ END MESSAGE ------------
''';

void main() {
  test('smtpd bytes-repr log: headers, multi-line body, two messages', () {
    final e = MailCatcherService.parseLog(_smtpdBytes);
    expect(e, hasLength(2));
    expect(e[0].subject, 'Hello there');
    expect(e[0].from, 'alice@example.com');
    expect(e[0].to, 'bob@example.com');
    expect(e[0].body, "line one\n\nline three: café and it's ok");
    expect(e[1].subject, 'Second');
    expect(e[1].from, 'carol@example.com');
    expect(e[1].body, 'only line');
  });

  test('aiosmtpd plain log: headers, multi-line body, two messages', () {
    final e = MailCatcherService.parseLog(_aiosmtpd);
    expect(e, hasLength(2));
    expect(e[0].subject, 'Hello there');
    expect(e[0].from, 'alice@example.com');
    expect(e[0].to, 'bob@example.com');
    expect(e[0].body, 'line one\n\nline three');
    expect(e[1].to, 'dave@example.com');
    expect(e[1].body, 'only line');
  });

  test('header-looking lines in the body are not parsed as headers', () {
    final e = MailCatcherService.parseLog('''
---------- MESSAGE FOLLOWS ----------
Subject: Real
From: a@b.c
To: d@e.f

Subject: fake
From: nobody
------------ END MESSAGE ------------
''');
    expect(e.single.subject, 'Real');
    expect(e.single.from, 'a@b.c');
    expect(e.single.body, 'Subject: fake\nFrom: nobody');
  });

  test('aiosmtpd mail options preamble before the headers is skipped', () {
    final e = MailCatcherService.parseLog('''
---------- MESSAGE FOLLOWS ----------
mail options: ['BODY=8BITMIME', 'SMTPUTF8']

From: alice@example.com
To: bob@example.com
Subject: Options
X-Peer: ('127.0.0.1', 51234)

hello body
------------ END MESSAGE ------------
''');
    expect(e, hasLength(1));
    expect(e.single.from, 'alice@example.com');
    expect(e.single.to, 'bob@example.com');
    expect(e.single.subject, 'Options');
    expect(e.single.body, 'hello body');
  });

  test('smtpd rcpt options preamble (plain and bytes-repr) is skipped', () {
    final e = MailCatcherService.parseLog('''
---------- MESSAGE FOLLOWS ----------
mail options: ['SIZE=120']
rcpt options: ['NOTIFY=NEVER']
b''
b'Subject: Rcpt'
b'From: a@example.com'
b'To: b@example.com'
X-Peer: 127.0.0.1
b''
b'the body'
------------ END MESSAGE ------------
---------- MESSAGE FOLLOWS ----------
b'rcpt options: []'
b'Subject: Two'
b'From: c@example.com'
b'To: d@example.com'
b''
b'second'
------------ END MESSAGE ------------
''');
    expect(e.map((m) => m.subject), ['Rcpt', 'Two']);
    expect(e.first.body, 'the body');
    expect(e.last.body, 'second');
  });

  test('empty log and unrelated text yield nothing', () {
    expect(MailCatcherService.parseLog(''), isEmpty);
    expect(MailCatcherService.parseLog('Server started\n'), isEmpty);
  });

  test('a NUL-prefixed MESSAGE FOLLOWS block still parses', () {
    final e = MailCatcherService.parseLog(
        '\u0000\u0000\u0000\u0000---------- MESSAGE FOLLOWS ----------\n'
        'Subject: After clear\nFrom: a@b.c\nTo: d@e.f\n\nbody\n'
        '------------ END MESSAGE ------------\n');
    expect(e.single.subject, 'After clear');
    expect(e.single.body, 'body');
  });

  test('start runs both servers unbuffered and in append mode', () async {
    final fake = FakeDevopsSsh(
      reply: (_) => (stdout: 'started:/tmp/mcx', stderr: '', exitCode: 0),
    );
    final host = Host(label: 'h', host: 'srv', port: 22, username: 'u');
    expect(await MailCatcherService(fake).start(host), isTrue);
    final cmd = fake.cmds.firstWhere((c) => c.contains('mktemp'));
    expect(
      cmd,
      contains('nohup python3 -u -m smtpd -n -c DebuggingServer localhost:1025 '
          '>> "\$d/log" 2>&1 &'),
    );
    expect(
      cmd,
      contains('nohup python3 -u -m aiosmtpd -n -l localhost:1025 '
          '>> "\$d/log" 2>&1 &'),
    );
    expect(cmd, contains("python3 -c 'import smtpd'"));
    expect(cmd, contains("python3 -c 'import aiosmtpd'"));
    expect(cmd, isNot(contains(' > "\$d/log"')));
  });
}
