# Prebuilt Linux desktop for RDP: KDE Plasma on Ubuntu 24.04 with Mint's icon theme.
# Built once by .github/workflows/image.yml, pushed to ghcr.io, then started in seconds by
# .github/workflows/prebuilt.yml instead of installing KDE on every run.

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    XDG_RUNTIME_DIR=/tmp/xdg-runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
      kde-plasma-desktop \
      plasma-workspace \
      plasma-widgets-addons \
      kwin-x11 \
      kscreen \
      plasma-nm \
      plasma-pa \
      systemsettings \
      konsole \
      dolphin \
      kate \
      xrdp \
      xorgxrdp \
      ssl-cert \
      xauth \
      dbus \
      dbus-x11 \
      x11-xserver-utils \
      fonts-dejavu-core \
      fonts-noto-color-emoji \
      sudo \
      curl \
      ca-certificates \
      git \
      procps \
      iproute2 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Linux Mint's own Mint-Y icon theme (best effort: it is cosmetic).
RUN git clone --depth 1 https://github.com/linuxmint/mint-y-icons.git /tmp/mint-y-icons \
    && cp -r /tmp/mint-y-icons/usr/share/icons/. /usr/share/icons/ \
    && (command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -f -t /usr/share/icons/Mint-Y || true) \
    && rm -rf /tmp/mint-y-icons

# Defaults for every user created at runtime: Mint-Y icons, no screen locker, no wallet prompt,
# no compositing (much smoother over RDP).
RUN mkdir -p /etc/xdg \
    && printf '[Icons]\nTheme=Mint-Y\n' > /etc/xdg/kdeglobals \
    && printf '[Daemon]\nAutolock=false\nLockOnResume=false\n' > /etc/xdg/kscreenlockerrc \
    && printf '[Wallet]\nEnabled=false\nFirst Use=false\n' > /etc/xdg/kwalletrc \
    && printf '[Compositing]\nEnabled=false\n' > /etc/xdg/kwinrc

# The session xrdp runs on every login: KDE Plasma on X11 with a session bus.
COPY startwm.sh /etc/xrdp/startwm.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /etc/xrdp/startwm.sh /usr/local/bin/entrypoint.sh

EXPOSE 3389

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
