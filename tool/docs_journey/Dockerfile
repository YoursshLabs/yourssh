# Demo SSH server image for the docs screenshot journey (see tool/docs_journey.sh).
# No secrets baked in: the client public key is installed at `setup` time.
# The demo/demo1234 password is a throwaway for a loopback-only demo container.
FROM alpine:latest
RUN apk add --no-cache openssh bash python3 py3-aiosmtpd htop git curl less vim tmux ncurses \
 && ssh-keygen -A \
 && adduser -D -s /bin/bash demo && echo 'demo:demo1234' | chpasswd \
 && mkdir -p /home/demo/.ssh /home/demo/projects/webapp/src /home/demo/logs /home/demo/backups \
 && printf 'server {\n  listen 80;\n  server_name demo.local;\n}\n' > /home/demo/projects/webapp/nginx.conf \
 && printf '# Web app\n\nDemo project used in the YourSSH docs.\n' > /home/demo/projects/webapp/README.md \
 && printf 'console.log("hello from yourssh-demo");\n' > /home/demo/projects/webapp/src/index.js \
 && for i in 1 2 3; do echo "2026-11-1$i 10:0$i:00 INFO request served in ${i}2ms" >> /home/demo/logs/app.log; done \
 && head -c 2097152 /dev/urandom > /home/demo/backups/db-2026-11-12.sql.gz \
 && printf 'export PS1="\\[\\e[1;32m\\]\\u@\\h\\[\\e[0m\\]:\\[\\e[1;34m\\]\\w\\[\\e[0m\\]\\$ "\nalias ll="ls -la"\n' > /home/demo/.bashrc \
 && printf '[ -f ~/.bashrc ] && . ~/.bashrc\n' > /home/demo/.bash_profile \
 && chown -R demo:demo /home/demo && chmod 700 /home/demo/.ssh \
 && sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/; s/^#\?AllowTcpForwarding.*/AllowTcpForwarding yes/; s/^#\?AllowAgentForwarding.*/AllowAgentForwarding yes/; s/^#\?GatewayPorts.*/GatewayPorts no/' /etc/ssh/sshd_config
EXPOSE 22
CMD ["/usr/sbin/sshd","-D","-e"]
