#!/bin/bash
# Container start-up: create the desktop user, then run xrdp in the foreground.
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
mkdir -p /run/xrdp /var/log/xrdp /var/lib/xrdp
chown xrdp:xrdp /run/xrdp /var/log/xrdp /var/lib/xrdp
adduser xrdp ssl-cert 2>/dev/null || true
if [ ! -s /etc/ssl/private/ssl-cert-snakeoil.key ]; then
  make-ssl-cert generate-default-snakeoil --force-overwrite || true
fi

# A system bus keeps parts of Plasma quiet about missing services.
mkdir -p /run/dbus
dbus-daemon --system --fork 2>/dev/null || true

# Session manager first, then xrdp in the foreground so the container stays alive
# and its logs go to `docker logs`.
xrdp-sesman
for _ in $(seq 1 15); do
  if pgrep -x xrdp-sesman >/dev/null; then
    break
  fi
  sleep 1
done
if ! pgrep -x xrdp-sesman >/dev/null; then
  echo "xrdp-sesman did not start; sessions would fail even though xrdp binds 3389" >&2
  exit 1
fi

echo "Starting xrdp on 0.0.0.0:3389"
xrdp --nodaemon &
xrdp_pid=$!

# xrdp opens its listening socket a moment after it starts. Say so when it does, and fail
# loudly when it never does, instead of leaving a container that looks up but answers nothing.
listening=0
for _ in $(seq 1 30); do
  if ss -ltn 2>/dev/null | grep -q ':3389'; then
    listening=1
    break
  fi
  if ! kill -0 "${xrdp_pid}" 2>/dev/null; then
    echo "xrdp exited during start-up; its log is above." >&2
    exit 1
  fi
  sleep 1
done

if [ "${listening}" -ne 1 ]; then
  echo "xrdp did not open port 3389 within 30 seconds; restarting it in the foreground for its log." >&2
  kill "${xrdp_pid}" 2>/dev/null || true
  exec xrdp --nodaemon
fi

echo "xrdp is listening on 0.0.0.0:3389"
wait "${xrdp_pid}"
