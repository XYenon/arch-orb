# arch-orb

[![Build and push image](https://github.com/XYenon/arch-orb/actions/workflows/build.yml/badge.svg)](https://github.com/XYenon/arch-orb/actions/workflows/build.yml)
[![lint](https://github.com/XYenon/arch-orb/actions/workflows/lint.yml/badge.svg)](https://github.com/XYenon/arch-orb/actions/workflows/lint.yml)
[![License: AGPL-3.0-or-later](https://img.shields.io/badge/License-AGPL_3.0-blue.svg)](LICENSE)

An Arch Linux image for [Amp self-hosted orbs](https://ampcode.com/docs/orbs/self-hosted#bring-your-own-image).

It starts from the official rolling `quay.io/archlinux/archlinux:latest` image,
adds the [archlinuxcn](https://www.archlinuxcn.org/archlinux-cn-repo-and-mirror/)
repository and [paru](https://github.com/Morganamilo/paru), installs Google
Chrome from the AUR, copies Amp's CLI and `/opt/amp-wayland` Desktop runtime from
Amp's published orb image, and installs Nix with its official single-user installer.

## Quick Start (Self-Hosted Provider)

You can run the provider with the pre-built GHCR image directly:

```bash
# Register the provider
amp orb provider create arch-orb

# Run the dispatch program with pre-built image
export ORB_IMAGE=ghcr.io/xyenon/arch-orb:latest
amp orb provider ./dispatch.sh
```

Or pick the provider via CLI:

```bash
amp -ox "your first message" --orb-provider arch-orb
```

> [!NOTE]
> If you built the image locally from source, set
> `export ORB_IMAGE=arch-orb:latest` instead.

`dispatch.sh` creates a container, runs `amp orb bootstrap` as the image's `user`,
stops the container on pause, commits it to `ORB_SNAPSHOT_ID` for project snapshots,
and removes it on delete. It boots the container with `sleep infinity` so systemd
does not run as PID 1, and Amp starts Portals, Terminal, and Desktop directly.

Set `CONTAINER_ENGINE=podman` to use Podman instead of Docker.

This image targets `x86_64`. The Dockerfile and `verify.sh` are x86_64-specific
(pinned x86_64 libxml2/ICU paths, the Chrome AUR package, and
`dpkg --print-architecture`), so an ARM64 build needs matching changes.
`ORB_PLATFORM` selects the runtime platform.

## Provider Notes

- `ORB_TYPE` is ignored: every orb gets the same container. If you configure
  orb types, extend `dispatch.sh` to map them to `--cpus`/`--memory`.
- The dispatch sets no CPU or memory limits; multiple orbs share the host.
- `docker commit` project snapshot images are local and are not deleted by
  Amp. Prune them periodically, or label them in `dispatch.sh` and clean them
  with a filter.
- Podman needs `catatonit` for the dispatch's `--init` flag; Arch's `podman`
  package depends on it.
- Bootstrap output is written to `~/.amp-bootstrap.log` inside the orb.

## What is included

- **Base & AUR**: Latest Arch Linux base (updated via `paru -Syu`),
  `archlinuxcn-keyring`, and `paru` AUR helper.
- **Desktop Runtime**: `/opt/amp-wayland` copied from Amp's published orb image
  (including `labwc`, `waymote-gateway`, and `waymote-streamd`), Google Chrome
  (AUR), Xwayland, dbus, gsettings-desktop-schemas, xsettingsd, wlr-randr,
  PulseAudio, ffmpeg, and DejaVu/Liberation fonts.
- **Amp Integration**: Amp CLI at `/usr/local/bin/amp` (symlink to the updatable
  `/home/user/.amp/bin/amp`), `agent-browser`, headless systemd units, and helper
  scripts.
- **Developer Tools**: bun, pnpm, yarn, corepack, uv, glab, gh, ripgrep, vim,
  websocat, ImageMagick (`magick`), and OpenSSH (with SSH commit signing).
- **Nix**: Latest Nix installed via the official single-user installer
  (`experimental-features = nix-command flakes`).
- **Terminal & Portals**: tmux with Amp's `tmux-sync-env` helper; Node.js and npm
  for Portals.
- **Permissions**: `user` (uid/gid 1000) with home directory `/home/user` and
  passwordless `sudo` access to all users and groups.

## Building from Source

The build uses Docker by default and targets `linux/amd64`:

```bash
./build.sh
```

Set `ORB_PLATFORM` to select another platform (with the matching `BASE_IMAGE`,
`AMP_IMAGE`, and Dockerfile changes). `BASE_IMAGE` and `AMP_IMAGE` select the
Arch base and the Amp source image.

To build using Podman instead:

```bash
CONTAINER_ENGINE=podman ./build.sh
```

By default it uses the official Arch mirror `https://geo.mirror.pkgbuild.com`
and archlinuxcn endpoint `https://repo.archlinuxcn.org`. To build with China
mirrors (e.g. BFSU):

```bash
ARCH_MIRROR=https://mirrors.bfsu.edu.cn/archlinux \
ARCHLINUXCN_MIRROR=https://mirrors.bfsu.edu.cn/archlinuxcn \
./build.sh
```

## Verification

The verification script checks the image against Amp's
[Bring Your Own Image contract](https://ampcode.com/docs/orbs/self-hosted#bring-your-own-image)
and the features those requirements enable:

```bash
# Podman
podman run --rm --shm-size=1g \
  -v "$PWD/verify.sh:/tmp/verify.sh:ro" \
  arch-orb:latest bash /tmp/verify.sh

# Docker
docker run --rm --shm-size=1g \
  -v "$PWD/verify.sh:/tmp/verify.sh:ro" \
  arch-orb:latest bash /tmp/verify.sh
```

A passing run ends with a summary reporting zero failures:

```text
Summary
  N passed, 0 failed
```

Both the default official-mirror build and a BFSU-mirror build pass this check.

## Technical Notes

- **Desktop runtime & libxml2 ABI**: The bundled `labwc` is a Debian build
  requiring `libxml2.so.2` (which Arch's libxml2 no longer provides). The image
  packages a pinned Arch archive of `libxml2` 2.13 and its ICU 76 dependency
  inside `/opt/amp-wayland/lib/x86_64-linux-gnu` without touching system libraries.
- **Google Chrome AUR alias**: Chrome is installed via the AUR package
  (`google-chrome-stable`). An alias symlink `/usr/bin/google-chrome` is created
  to satisfy Amp's Desktop launch expectation.
- **Desktop app installers**: Amp Desktop's optional app installers (Firefox,
  VS Code, Blender) assume Debian `apt-get` and do not function on Arch. Chrome
  is preinstalled; other GUI tools should be installed with `paru`.
- **Nix single-user setup**: Nix is installed with the latest official
  single-user installer (`--no-daemon`, `--no-channel-add`) into user-owned `/nix`,
  with `/usr/local/bin` symlinks and default flakes enabled.
- **Agent Browser**: `agent-browser` is copied directly from Amp's published orb
  image so the Desktop/MCP runtime matches the official version.
- **Amp systemd units & isolation**: Headless units and helper scripts
  (`amp-headless*`, `amp.slice`, `amp-control.slice`, `amp-workload.slice`,
  `amp-run-workload`) are copied from the official image. `websocat.service` is
  pointed at Arch's `sshd.service` and `/usr/local/bin/websocat`.
- **Amp self-updates**: `/usr/local/bin/amp` points to `/home/user/.amp/bin/amp`,
  allowing seamless in-place self-updates on startup.
- **Package cleanup**: After paru is installed, the image uses paru for package
  operations and cleanup (`paru -Syu`, `paru -Scc`, and `--cleanafter` for AUR
  builds).

## GitHub Actions

- `.github/workflows/build.yml`: Builds `linux/amd64` with Buildx and pushes to
  `ghcr.io/xyenon/arch-orb` on pushes to `master`, version tags, and manual
  triggers. Pull requests build without pushing. The workflow does not run
  `verify.sh`; run it locally or add a verification step before relying on a
  pushed image.
- `.github/workflows/lint.yml`: Validates workflows with `jactionlint`, shell
  scripts with `shellcheck` + `shfmt -d`, and Markdown files with `rumdl`.

## License

The source code in this repository is licensed under the GNU Affero General
Public License, version 3 or later (`AGPL-3.0-or-later`). See [`LICENSE`](LICENSE).

The built image contains third-party components under their own licenses and
terms; see [`THIRD_PARTY.md`](THIRD_PARTY.md). Chrome and Amp components are not
covered by the AGPL and remain subject to their respective terms.
