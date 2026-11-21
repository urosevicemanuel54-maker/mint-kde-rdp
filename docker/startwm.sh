#!/bin/bash
# Session started by xrdp on every RDP login.
if [ -r /etc/profile ]; then . /etc/profile; fi
if [ -f "$HOME/.profile" ]; then . "$HOME/.profile"; fi

export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=KDE
export XDG_SESSION_DESKTOP=KDE
export DESKTOP_SESSION=plasma
export XDG_RUNTIME_DIR="/tmp/xrdp-runtime-$USER"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

exec dbus-run-session -- startplasma-x11
