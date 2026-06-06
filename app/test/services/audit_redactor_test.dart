import 'package:flutter_test/flutter_test.dart';
import 'package:yourssh/services/audit_redactor.dart';

void main() {
  String r(String s) => AuditRedactor.redact(s);

  test('key=value secrets are masked, key kept', () {
    expect(r('mysql -u root password=hunter2'),
        'mysql -u root password=[REDACTED]');
    expect(r('export API_KEY=abc123'), 'export API_KEY=[REDACTED]');
    expect(r('TOKEN=t SECRET=s'), 'TOKEN=[REDACTED] SECRET=[REDACTED]');
    expect(r('PGPASSWORD=pg psql -h db'), 'PGPASSWORD=[REDACTED] psql -h db');
    expect(r('curl -d passwd=x'), 'curl -d passwd=[REDACTED]');
  });

  test('Authorization: Bearer is masked', () {
    expect(r("curl -H 'Authorization: Bearer eyJabc'"),
        "curl -H 'Authorization: Bearer [REDACTED]'");
  });

  test('sshpass -p is masked', () {
    expect(r('sshpass -p s3cret ssh u@h'), 'sshpass -p [REDACTED] ssh u@h');
  });

  test('mysql/mariadb attached -p is masked', () {
    expect(r('mysql -u root -ps3cret db'), 'mysql -u root -p[REDACTED] db');
    expect(r('mariadb -psecret'), 'mariadb -p[REDACTED]');
  });

  test('psql -p stays untouched (port, not password)', () {
    expect(r('psql -p 5432 -h db'), 'psql -p 5432 -h db');
  });

  test('URL userinfo password is masked', () {
    expect(r('curl https://user:pw@example.com/x'),
        'curl https://user:[REDACTED]@example.com/x');
  });

  test('no false positives', () {
    expect(r('cat password.txt'), 'cat password.txt');
    expect(r('ls -la /srv'), 'ls -la /srv');
    expect(r('echo token bucket'), 'echo token bucket');
  });
}
