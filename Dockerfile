# syntax=docker/dockerfile:1.7
#
# Arch Linux image for Amp self-hosted orbs.
# See https://ampcode.com/docs/orbs/self-hosted#bring-your-own-image
#
# The Amp CLI and /opt/amp-wayland are copied from Amp's published orb image so
# Desktop and the CLI update path behave exactly like they do on Amp-hosted orbs.
# Nix is installed with its official single-user installer.
#
# Bootstrap with pacman only until paru exists: the archlinuxcn keyring, the
# orb user, sudo, and paru itself. After paru is installed, every package
# operation and cache cleanup goes through paru, including Chrome from the AUR.
#
# Layers run from the least to the most frequently changed input, so a rebuild
# reuses everything above the edit. Package installs and Nix come first because
# they cost minutes and only change with the package list. The pinned
# compatibility libraries come next, then the files copied from Amp's image,
# and last the permission fixes and licensing files that are cheap to redo.

ARG AMP_IMAGE=us-central1-docker.pkg.dev/amp-prod-0/amp-orb/amp-orb:latest
ARG BASE_IMAGE=quay.io/archlinux/archlinux:latest

FROM ${AMP_IMAGE} AS amp

FROM ${BASE_IMAGE}

ARG BASE_IMAGE
ARG ARCH_MIRROR=https://geo.mirror.pkgbuild.com
ARG ARCHLINUXCN_MIRROR=https://repo.archlinuxcn.org

LABEL org.opencontainers.image.title="arch-orb" \
      org.opencontainers.image.description="Arch Linux image for Amp self-hosted orbs" \
      org.opencontainers.image.source="https://github.com/XYenon/arch-orb" \
      org.opencontainers.image.base.name="${BASE_IMAGE}"

ENV LANG=C.UTF-8 \
    HOME=/home/user \
    USER=user \
    LOGNAME=user \
    PATH=/opt/amp-wayland/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LD_LIBRARY_PATH=/opt/amp-wayland/lib/x86_64-linux-gnu:/opt/amp-wayland/lib \
    NODE_OPTIONS=--use-system-ca

# Configure archlinuxcn, bootstrap its keyring with pacman, upgrade the rolling
# base in full, create the orb user, install sudo and paru, then hand package
# management to paru. The full upgrade comes before any package install so the
# base never runs a partial upgrade: archlinuxcn builds paru against the current
# Arch tree, and installing it onto a stale base fails on glibc. The paru cleanup
# in this same layer removes the bootstrap package cache.
RUN if [ "${ARCH_MIRROR}" = "https://geo.mirror.pkgbuild.com" ]; then \
      printf 'Server = %s/$repo/os/$arch\n' "${ARCH_MIRROR}" > /etc/pacman.d/mirrorlist; \
    else \
      printf 'Server = %s/$repo/os/$arch\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n' "${ARCH_MIRROR}" > /etc/pacman.d/mirrorlist; \
    fi \
 && if [ "${ARCHLINUXCN_MIRROR}" = "https://repo.archlinuxcn.org" ]; then \
      printf 'Server = %s/$arch\n' "${ARCHLINUXCN_MIRROR}" > /etc/pacman.d/archlinuxcn-mirrorlist; \
    else \
      printf 'Server = %s/$arch\nServer = https://repo.archlinuxcn.org/$arch\n' "${ARCHLINUXCN_MIRROR}" > /etc/pacman.d/archlinuxcn-mirrorlist; \
    fi \
 && printf '\n[archlinuxcn]\nInclude = /etc/pacman.d/archlinuxcn-mirrorlist\nSigLevel = Never\n' \
      >> /etc/pacman.conf \
 && pacman-key --init \
 && pacman -Sy --noconfirm archlinuxcn-keyring \
 && pacman-key --populate archlinux archlinuxcn \
 && sed -i '/^SigLevel = Never$/d' /etc/pacman.conf \
 && pacman -Syu --noconfirm \
 && pacman -S --noconfirm --needed sudo shadow \
 && groupadd -g 1000 user \
 && (getent group wheel >/dev/null || groupadd wheel) \
 && useradd -u 1000 -g user -G wheel -m -d /home/user -s /bin/bash user \
 && install -d -o user -g user -m 0755 \
      /home/user/.amp/bin /home/user/.config /home/user/.local /home/user/.cache \
 && (grep -q '^@includedir /etc/sudoers.d' /etc/sudoers \
      || printf '@includedir /etc/sudoers.d\n' >> /etc/sudoers) \
 && printf 'user ALL=(ALL:ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/99-user \
 && printf 'Defaults!/usr/bin/systemd-run !use_pty\n' > /etc/sudoers.d/amp-systemd-run \
 && chmod 0440 /etc/sudoers.d/99-user /etc/sudoers.d/amp-systemd-run \
 && printf '%s\n' \
      'export AMP_BIN_DIR="${AMP_BIN_DIR:-$HOME/.amp/bin}"' \
      'export PATH="$HOME/.amp/bin:$HOME/.local/bin:$PATH"' \
      > /home/user/.bashrc \
 && chown -R user:user /home/user \
 && pacman -S --noconfirm --needed paru \
 && su -s /bin/bash user -c \
      'set -e; export HOME=/home/user USER=user LOGNAME=user; printf "y\ny\ny\ny\n" | paru -Scc'

# paru owns the rest of package management. The base is already current from the
# layer above, so this only installs the orb contract and Desktop packages and
# clears the cache afterwards.
RUN su -s /bin/bash user -c \
      'set -e; export HOME=/home/user USER=user LOGNAME=user; paru -S --noconfirm --needed bash coreutils util-linux ca-certificates git sudo shadow systemd ncurses nodejs npm tmux curl wget ripgrep openssh github-cli jq procps-ng findutils which tar gzip xz zstd unzip python python-pip dpkg openssl base-devel libarchive xorg-xwayland dbus gsettings-desktop-schemas xsettingsd wlr-randr pulseaudio ffmpeg ttf-dejavu ttf-liberation adwaita-icon-theme fontconfig seatd libdisplay-info libliftoff libinput xcb-util-wm libxml2 mesa libxkbcommon labwc swaybg foot gtk3 at-spi2-core nss nspr libcups alsa-lib expat glib2 cairo pango libx11 libxcb libxcomposite libxdamage libxext libxfixes libxrandr libxrender libxss libxtst libxi libxcursor libxshmfence vulkan-icd-loader xdg-utils pciutils bun pnpm yarn corepack uv glab imagemagick websocat vim; printf "y\ny\ny\ny\n" | paru -Scc'

# Chrome comes from the AUR in its own layer: it is the part most likely to need
# a fix, and a separate layer keeps those fixes from re-downloading the packages
# above. The AUR's beta, canary, and dev packages all provide google-chrome, so
# the provider prompt is answered explicitly with the plain package instead of
# relying on its default. --cleanafter removes AUR build directories and -Scc
# removes the package cache, but paru keeps its AUR clone, so that directory is
# deleted here too and nothing historical is baked into the image.
RUN su -s /bin/bash user -c \
      'set -e; export HOME=/home/user USER=user LOGNAME=user; printf "1\n" | paru -S --noconfirm --needed --skipreview --cleanafter --removemake google-chrome; printf "y\ny\ny\ny\n" | paru -Scc' \
 && rm -rf /home/user/.cache/paru \
 && ln -sf /usr/bin/google-chrome-stable /usr/bin/google-chrome \
 && chown root:root /opt/google/chrome/chrome-sandbox \
 && chmod 4755 /opt/google/chrome/chrome-sandbox \
 && su -s /bin/bash user -c 'export HOME=/home/user; google-chrome --version'

# Install Nix with its official single-user installer. The installer creates a
# user-owned /nix store and profile; recreate the same /usr/local/bin/nix*
# symlinks and nix.conf that Amp's image uses. This depends on nothing from
# Amp's image, so it sits above the copies to keep its minutes out of the way of
# edits to them.
RUN su -s /bin/bash user -c \
      'set -e; export HOME=/home/user USER=user LOGNAME=user; curl -fsSL https://nixos.org/nix/install -o /tmp/nix-install.sh; sh /tmp/nix-install.sh --no-daemon --no-channel-add' \
 && chgrp user /nix \
 && install -d /etc/nix \
 && printf 'experimental-features = nix-command flakes\n' > /etc/nix/nix.conf \
 && ln -sf /home/user/.nix-profile/bin/* /usr/local/bin/ \
 && chown -R user:user /nix /home/user/.local/state/nix \
 && su -s /bin/bash user -c 'export HOME=/home/user; nix --version; nix-shell --version'

COPY --from=amp /opt/amp-wayland /opt/amp-wayland

# Debian's labwc in /opt/amp-wayland links libxml2.so.2, while current Arch
# libxml2 ships libxml2.so.16. Keep the bundled labwc and give it an
# Arch-built libxml2 2.13 plus its ICU 76 dependency inside the bundle. The
# archive URLs are pinned, so this layer only changes with the copy above.
RUN mkdir -p /tmp/compat \
 && curl -fsSL -o /tmp/compat/libxml2.pkg.tar.zst \
      https://archive.archlinux.org/packages/l/libxml2/libxml2-2.13.8-1-x86_64.pkg.tar.zst \
 && bsdtar -xf /tmp/compat/libxml2.pkg.tar.zst -C /tmp/compat \
 && curl -fsSL -o /tmp/compat/icu.pkg.tar.zst \
      https://archive.archlinux.org/packages/i/icu/icu-76.1-1-x86_64.pkg.tar.zst \
 && mkdir -p /tmp/compat/icu \
 && bsdtar -xf /tmp/compat/icu.pkg.tar.zst -C /tmp/compat/icu \
 && install -m 0644 /tmp/compat/usr/lib/libxml2.so.2.13.8 \
      /opt/amp-wayland/lib/x86_64-linux-gnu/libxml2.so.2.13.8 \
 && install -m 0644 /tmp/compat/icu/usr/lib/libicuuc.so.76.1 \
      /opt/amp-wayland/lib/x86_64-linux-gnu/libicuuc.so.76.1 \
 && install -m 0644 /tmp/compat/icu/usr/lib/libicudata.so.76.1 \
      /opt/amp-wayland/lib/x86_64-linux-gnu/libicudata.so.76.1 \
 && ln -sf libxml2.so.2.13.8 /opt/amp-wayland/lib/x86_64-linux-gnu/libxml2.so.2 \
 && ln -sf libicuuc.so.76.1 /opt/amp-wayland/lib/x86_64-linux-gnu/libicuuc.so.76 \
 && ln -sf libicudata.so.76.1 /opt/amp-wayland/lib/x86_64-linux-gnu/libicudata.so.76 \
 && rm -rf /tmp/compat \
 && chown -R root:root /opt/amp-wayland \
 && chmod -R a+rX /opt/amp-wayland

COPY --from=amp /home/user/.amp/bin/amp /home/user/.amp/bin/amp
COPY --from=amp /home/user/.tmux.conf /home/user/.tmux.conf
COPY --from=amp /usr/local/bin/tmux-sync-env /usr/local/bin/tmux-sync-env
COPY --from=amp /usr/local/lib/node_modules/agent-browser/package.json /usr/local/lib/node_modules/agent-browser/package.json
COPY --from=amp /usr/local/lib/node_modules/agent-browser/bin/agent-browser.js /usr/local/lib/node_modules/agent-browser/bin/agent-browser.js
COPY --from=amp /usr/local/lib/node_modules/agent-browser/bin/agent-browser-linux-x64 /usr/local/lib/node_modules/agent-browser/bin/agent-browser-linux-x64
COPY --from=amp /usr/local/lib/node_modules/agent-browser/bin/.install-method /usr/local/lib/node_modules/agent-browser/bin/.install-method
COPY --from=amp /usr/local/lib/node_modules/agent-browser/skills /usr/local/lib/node_modules/agent-browser/skills
COPY --from=amp /usr/local/lib/node_modules/agent-browser/skill-data /usr/local/lib/node_modules/agent-browser/skill-data
COPY --from=amp /usr/local/lib/node_modules/agent-browser/scripts /usr/local/lib/node_modules/agent-browser/scripts

# Amp's headless systemd units and helper scripts come from the official image.
# Docker-backed orbs boot the container with `sleep infinity`, so systemd never
# runs and these stay inert; they matter on hosts that start systemd as PID 1.
COPY --from=amp /etc/systemd/system/amp.slice /etc/systemd/system/amp-control.slice \
     /etc/systemd/system/amp-workload.slice /etc/systemd/system/amp-headless.service \
     /etc/systemd/system/amp-headless-bootstrap.service /etc/systemd/system/amp-headless-env.service \
     /etc/systemd/system/amp-headless-env.path /etc/systemd/system/websocat.service \
     /etc/systemd/system/
COPY --from=amp /usr/local/bin/amp-headless-apply-env /usr/local/bin/amp-headless-update-binary \
     /usr/local/bin/amp-run-workload /usr/local/bin/amp-validate-workload-cgroups \
     /usr/local/bin/
COPY --from=amp /home/user/.amp/prepared-headless-release /home/user/.amp/prepared-headless-release

# Arch names the SSH unit sshd.service and installs websocat to /usr/bin, so the
# copied websocat unit is pointed at those, and the drop-in that keeps sshd in
# amp-control.slice is recreated for sshd.service. Enabled units mirror the
# official image: the headless executor itself is enabled at runtime, not here.
# The permission fixes for the copies above live here too, so tuning them never
# rebuilds a download.
RUN sed -i 's/ssh\.service/sshd.service/g' /etc/systemd/system/websocat.service \
 && install -d /etc/systemd/system/sshd.service.d \
 && printf '[Service]\nSlice=amp-control.slice\n' \
      > /etc/systemd/system/sshd.service.d/amp-control.conf \
 && install -d /etc/systemd/system/multi-user.target.wants \
 && ln -sf /etc/systemd/system/amp-headless-env.path \
      /etc/systemd/system/multi-user.target.wants/amp-headless-env.path \
 && ln -sf /usr/lib/systemd/system/sshd.service \
      /etc/systemd/system/multi-user.target.wants/sshd.service \
 && ln -sf /etc/systemd/system/websocat.service \
      /etc/systemd/system/multi-user.target.wants/websocat.service \
 && ln -sf /usr/bin/websocat /usr/local/bin/websocat \
 && chmod 0755 /usr/local/bin/amp-headless-apply-env /usr/local/bin/amp-headless-update-binary \
      /usr/local/bin/amp-run-workload /usr/local/bin/amp-validate-workload-cgroups \
 && chown user:user /home/user/.amp/prepared-headless-release \
 && chmod 0644 /home/user/.amp/prepared-headless-release \
 && chown -R root:root /usr/local/lib/node_modules/agent-browser \
 && chmod -R a+rX /usr/local/lib/node_modules/agent-browser \
 && chmod 0755 /usr/local/lib/node_modules/agent-browser/bin/agent-browser-linux-x64 \
 && chmod 0755 /usr/local/bin/tmux-sync-env \
 && chown user:user /home/user/.amp/bin/amp /home/user/.tmux.conf \
 && chmod 0755 /home/user/.amp/bin/amp \
 && ln -sf /home/user/.amp/bin/amp /usr/local/bin/amp \
 && ln -sf /usr/local/lib/node_modules/agent-browser/bin/agent-browser-linux-x64 /usr/local/bin/agent-browser

COPY LICENSE THIRD_PARTY.md /usr/share/licenses/arch-orb/
COPY --from=amp /usr/local/lib/node_modules/agent-browser/LICENSE /usr/local/lib/node_modules/agent-browser/LICENSE
LABEL org.opencontainers.image.licenses="AGPL-3.0-or-later"

RUN dbus-uuidgen --ensure=/etc/machine-id

USER user
WORKDIR /home/user
CMD ["sleep", "infinity"]
