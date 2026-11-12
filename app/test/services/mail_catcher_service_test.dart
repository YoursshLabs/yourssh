import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/mail_catcher_service.dart';

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

  test('empty log and unrelated text yield nothing', () {
    expect(MailCatcherService.parseLog(''), isEmpty);
    expect(MailCatcherService.parseLog('Server started\n'), isEmpty);
  });
}
