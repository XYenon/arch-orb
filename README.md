# arch-orb

An Arch Linux image for [Amp self-hosted
orbs](https://ampcode.com/docs/orbs/self-hosted#bring-your-own-image). The
repository is at [XYenon/arch-orb](https://github.com/XYenon/arch-orb).

It starts from the official rolling `quay.io/archlinux/archlinux:latest` image,
adds the
[archlinuxcn](https://www.archlinuxcn.org/archlinux-cn-repo-and-mirror/)
repository and [paru](https://github.com/Morganamilo/paru), installs Google
Chrome from the AUR, copies Amp's CLI and `/opt/amp-wayland` Desktop runtime
from Amp's published orb image, and installs Nix with its official single-user
installer.

## What is included

- Latest Arch Linux base, updated with `paru -Syu` during the build.
- archlinuxcn repository with `archlinuxcn-keyring`, its official endpoint by
  default, and `paru`.
- Google Chrome installed with `paru` from the AUR.
- Amp CLI at `/usr/local/bin/amp` (symlink to the updatable
  `/home/user/.amp/bin/amp`).
- `/opt/amp-wayland` from Amp's orb image, including `labwc`, `waymote-gateway`,
  and `waymote-streamd`.
- Desktop dependencies: Xwayland, dbus, gsettings-desktop-schemas, xsettingsd,
  wlr-randr, PulseAudio, ffmpeg, DejaVu/Liberation fonts, and Chrome.
- Portals: Node.js and npm.
- Terminal: tmux and Amp's `tmux-sync-env` helper.
- Git with SSH commit signing, gh, ripgrep, and OpenSSH.
- Official-image developer tools: bun, pnpm, yarn, corepack, uv, glab,
  ImageMagick (`magick`), websocat, vim, and the latest Nix from the official
  single-user installer.
- `agent-browser` copied from Amp's published image.
- Amp's headless systemd units and helper scripts, copied from Amp's published
  image.
- The `user` user/group at uid/gid 1000, writable `/home/user`, and passwordless
  sudo to any user and group.

The image is designed for Docker/Podman-backed orbs. `dispatch.sh` boots the
container with `sleep infinity`, so systemd never runs and Amp starts Portals,
Terminal, and Desktop itself. The headless units ship for hosts that start
systemd as PID 1 and stay inert otherwise.

## Build

The build uses Podman by default:

```bash
./build.sh
```

Use Docker with the same Dockerfile if you prefer:

```bash
docker build -t arch-orb:latest .
```

The build pulls Amp's orb image once to copy the CLI and Desktop runtime, then
builds on the Arch base and installs Nix separately. By default it uses the
official Arch mirror `https://geo.mirror.pkgbuild.com` and the official
archlinuxcn endpoint `https://repo.archlinuxcn.org`. To build with BFSU mirrors
instead:

```bash
ARCH_MIRROR=https://mirrors.bfsu.edu.cn/archlinux \
ARCHLINUXCN_MIRROR=https://mirrors.bfsu.edu.cn/archlinuxcn \
./build.sh
```

## Verify

The verification script checks every item in the Bring Your Own Image contract
plus the features those requirements enable:

```bash
podman run --rm --shm-size=1g \
  -v "$PWD/verify.sh:/tmp/verify.sh:ro" \
  arch-orb:latest bash /tmp/verify.sh
```

It covers the user and sudo contract, CA certificates, git signing, the Amp CLI,
archlinuxcn, paru, AUR Chrome, Node.js HTTP serving, tmux sessions, licensing
files, the additional official-image developer tools and Nix layout, the bundled
Desktop runtime, a headless labwc session with wlr-randr, Xwayland, xsettingsd,
PulseAudio, and Chrome headless with its sandbox enabled. A passing run ends
with a summary that reports zero failures:

```text
Summary
  N passed, 0 failed
```

Both the default official-mirror build and a BFSU-mirror build pass this check.

## GitHub Actions

`.github/workflows/build.yml` builds the image on pushes to `master`, version
tags, pull requests, and manual dispatch. Pull requests build without pushing;
other runs push to `ghcr.io/xyenon/arch-orb` using the workflow's
`GITHUB_TOKEN`. The workflow builds `linux/amd64` with Buildx and GitHub Actions
cache, and tags `master`, version, and commit images, with `latest` on the default
branch.

The GHCR package is private by default. Make it public from the package settings
if needed. The workflow requests `packages: write` and `id-token: write` at job
level; no extra registry secret is required. A separate
`.github/workflows/lint.yml` runs `jdx/jactionlint` on the workflow files,
`shellcheck` plus `shfmt -d` on every tracked `*.sh` file, and `rumdl` on every
tracked `*.md` file.

## License

The source code in this repository is licensed under the GNU Affero General
Public License, version 3 or later (`AGPL-3.0-or-later`). See
[`LICENSE`](LICENSE).

The built image contains third-party components under their own licenses and
terms; see [`THIRD_PARTY.md`](THIRD_PARTY.md). Chrome and Amp components are not
covered by the AGPL and remain subject to their respective terms.

## Use with a self-hosted provider

Register a provider and run the dispatch program:

```bash
amp orb provider create arch-orb
export ORB_IMAGE=arch-orb:latest
amp orb provider ./dispatch.sh
```

Then pick the provider in the new-thread composer, or from the CLI:

```bash
amp -ox "your first message" --orb-provider arch-orb
```

`dispatch.sh` creates a Podman container, runs `amp orb bootstrap` as the
image's `user`, stops the container on pause, commits it to `ORB_SNAPSHOT_ID`
when Amp asks for a project snapshot, and removes it on delete. Set
`CONTAINER_ENGINE=docker` to use Docker instead of Podman; the dispatch script
adapts its existence checks for either engine.

Set `ORB_IMAGE=arch-orb:latest` in the provider environment. Otherwise Amp
passes its default orb image to `spawn` jobs. This image is built for x86_64;
for ARM64 use an ARM64 Arch base, the ARM64 Chrome package, and
`ORB_PLATFORM=linux/arm64`.

## Notes

- The bundled `labwc` is a Debian build and expects `libxml2.so.2`, which Arch's
  libxml2 no longer provides. The image adds the libxml2 build pinned in the
  Dockerfile, plus the ICU it links against, inside
  `/opt/amp-wayland/lib/x86_64-linux-gnu`. The system library is untouched.
- Chrome is installed from the AUR, not extracted from a Debian `.deb` by hand.
  The AUR package installs the launcher as `google-chrome-stable`; the image
  adds the `google-chrome` alias that Amp's Desktop code expects.
- Desktop's optional app installer uses Debian `apt-get` for Firefox, VS Code,
  Blender, and similar apps. Those installers do not work on Arch. Chrome itself
  is preinstalled, so the Desktop tab's browser is available. Install other
  desktop apps with `paru` and adjust the Desktop app scripts if needed.
- Nix is installed with the latest official single-user installer
  (`--no-daemon`). The installer creates the user-owned `/nix` store and
  profile; the image adds `/usr/local/bin` symlinks and `nix.conf`, without
  Arch's multi-user `nix` package and systemd units. `--no-channel-add` avoids a
  slow nixpkgs channel fetch during the build.
- `agent-browser` is copied from Amp's image so the Desktop/MCP Apps runtime
  matches the official version; the AUR package is newer and carries an
  all-platform payload.
- Amp's headless units and helper scripts (`amp-headless*`, `amp.slice`,
  `amp-control.slice`, `amp-workload.slice`, `amp-run-workload`,
  `amp-validate-workload-cgroups`) are copied from the official image, with
  `websocat.service` pointed at Arch's `sshd.service` and
  `/usr/local/bin/websocat`, plus an `sshd.service.d` drop-in that keeps sshd in
  `amp-control.slice`. Workload isolation only engages when
  `AMP_ORB_WORKLOAD_SLICE` is set, which `dispatch.sh` never does. The
  Debian-only pieces stay out: the Docker CLI and `apt-get`.
- `user` may sudo to any user and group (`user ALL=(ALL:ALL) NOPASSWD: ALL`),
  and `/etc/sudoers.d/amp-systemd-run` keeps workload pipes intact for
  `systemd-run`, matching the official image.
- `amp` updates itself on first start and keeps working because
  `/usr/local/bin/amp` points at `/home/user/.amp/bin/amp`.
- After paru is installed, the image uses paru for package operations and
  cleanup: `paru -Syu`, `paru -S`, `paru -Scc`, and `--cleanafter` for AUR
  builds. paru keeps its AUR clone after a build, so that directory is removed
  explicitly as well.
- `rumdl` checks the Markdown files with its default rules, which do not enforce
  a column limit, so the license table in `THIRD_PARTY.md` needs no exception.
