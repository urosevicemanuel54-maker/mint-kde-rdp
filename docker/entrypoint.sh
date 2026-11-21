#!/bin/bash
# Container start-up: create the desktop user, prepare xrdp the way the working Linux RDP
# setups do, start xrdp-sesman and xrdp, and keep the container alive while xrdp runs.
set -euo pipefail

user_name="${RDP_USER:-mint}"
user_password="${RDP_PASSWORD:-}"

if [ -z "${user_password}" ]; then
  echo "RDP_PASSWORD is required" >&2
  exit 1
fi

if ! id -u "${user_name}" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "${user_name}"
fi
printf '%s:%s\n' "${user_name}" "${user_password}" | chpasswd
usermod -aG sudo,ssl-cert "${user_name}"
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "${user_name}" > "/etc/sudoers.d/90-${user_name}"
chmod 0440 "/etc/sudoers.d/90-${user_name}"

# xrdp needs these before it will bind its port (a container never runs boot-time tmpfiles).
mkdir -p /run/xrdp /var/log/xrdp /var/lib/xrdp /run/dbus
chown xrdp:xrdp /run/xrdp /var/log/xrdp /var/lib/xrdp
adduser xrdp ssl-cert 2>/dev/null || true
usermod -aG shadow xrdp 2>/dev/null || true

# By default xrdp-sesman admits only members of the tsusers group, and that group does not
# exist in a container, so every login would be refused. Create it, admit our user and drop
# the restriction from sesman.ini (the same fix the working Linux RDP setups use).
groupadd -f tsusers
usermod -aG tsusers "${user_name}"
if [ -f /etc/xrdp/sesman.ini ]; then
  sed -i -E 's/^TerminalServerUsers=/#TerminalServerUsers=/; s/^TerminalServerAdmins=/#TerminalServerAdmins=/' /etc/xrdp/sesman.ini
fi

# xrdp's own TLS key pair, which xrdp-keygen makes on a normal install. Create it if the image
# lacks it, as the working setups do.
if [ ! -s /etc/xrdp/key.pem ] || [ ! -s /etc/xrdp/cert.pem ]; then
  if command -v xrdp-keygen >/dev/null 2>&1; then
    xrdp-keygen xrdp auto || echo "xrdp-keygen failed; xrdp may refuse connections" >&2
  fi
fi

# Session authentication: plain pam_unix for xrdp-sesman, the rule the working xrdp setups use.
# The stock Ubuntu rules expect logind and audit, which a container does not have.
printf '%s\n' \
  'auth required pam_unix.so' \
  'account required pam_unix.so' \
  'password required pam_unix.so' \
  'session required pam_unix.so' > /etc/pam.d/xrdp-sesman

dbus-daemon --system --fork 2>/dev/null || true

# Session manager first, then xrdp.
xrdp-sesman
for _ in $(seq 1 15); do
  if pgrep -x xrdp-sesman >/dev/null; then
    break
  fi
  sleep 1
done
if ! pgrep -x xrdp-sesman >/dev/null; then
  echo "xrdp-sesman did not start; sessions would fail even though xrdp binds 3389" >&2
  cat /var/log/xrdp-sesman.log 2>/dev/null || true
  exit 1
fi

echo "Starting xrdp on 0.0.0.0:3389"
xrdp --nodaemon &
xrdp_pid=$!

# xrdp opens its listening socket a moment after it starts. Say so when it does, and fail
# loudly with its logs when it never does.
listening=0
for _ in $(seq 1 30); do
  if ss -ltn 2>/dev/null | grep -q ':3389'; then
    listening=1
    break
  fi
  if ! kill -0 "${xrdp_pid}" 2>/dev/null; then
    echo "xrdp exited during start-up; its log is above." >&2
    cat /var/log/xrdp.log 2>/dev/null || true
    exit 1
  fi
  sleep 1
done

if [ "${listening}" -ne 1 ]; then
  echo "xrdp did not open port 3389 within 30 seconds. Port setting and logs follow." >&2
  grep -E '^port|^use_vsock|^security_layer' /etc/xrdp/xrdp.ini >&2 || true
  ls -l /etc/xrdp/*.pem >&2 || true
  cat /var/log/xrdp.log /var/log/xrdp-sesman.log 2>/dev/null >&2 || true
  kill "${xrdp_pid}" 2>/dev/null || true
  exec xrdp --nodaemon
fi

echo "xrdp is listening on 0.0.0.0:3389"
wait "${xrdp_pid}"
