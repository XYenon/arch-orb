#!/usr/bin/env bash
# Verify the Arch orb image against the Bring Your Own Image contract and the
# features that image enables (Portals, Terminal, Desktop, git, Amp CLI).
#
# Run from the host:
#   docker run --rm --shm-size=1g -v "$PWD/verify.sh:/tmp/verify.sh:ro" \
#     arch-orb:latest bash /tmp/verify.sh
#
# The script runs as the image's default "user"; it uses sudo where the orb
# contract expects passwordless sudo to work.

set -uo pipefail

PASS=0
FAIL=0
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

ok() {
	printf '  ok    %s\n' "$1"
	PASS=$((PASS + 1))
}

bad() {
	printf '  FAIL  %s\n' "$1"
	FAIL=$((FAIL + 1))
}

check() {
	local description=$1
	shift
	if "$@" >/dev/null 2>&1; then
		ok "$description"
	else
		bad "$description"
	fi
}

version_at_least() {
	local have=$1
	local want=$2
	[ "$(printf '%s\n%s\n' "$want" "$have" | sort -V | head -n1)" = "$want" ]
}

check_no_missing_libs() {
	local description=$1
	local binary=$2
	if ldd "$binary" 2>&1 | grep -q 'not found'; then
		bad "$description"
		ldd "$binary" 2>&1 | grep 'not found' | sed 's/^/        /'
	else
		ok "$description"
	fi
}

section() {
	printf '\n%s\n' "$1"
}

section "Base image"
if grep -q '^ID=arch' /etc/os-release; then ok "Arch Linux base"; else bad "Arch Linux base"; fi
printf '        %s\n' "$(grep PRETTY_NAME /etc/os-release | cut -d= -f2- | tr -d '"')"
printf '        %s\n' "$(grep VERSION_ID /etc/os-release | cut -d= -f2- | tr -d '"')"
if [ "$(uname -m)" = "x86_64" ]; then ok "x86_64 architecture"; else bad "x86_64 architecture"; fi
check "bash, coreutils, util-linux" bash -c 'command -v bash ls date flock mount findmnt >/dev/null'
check "CA certificate bundle" test -s /etc/ssl/certs/ca-certificates.crt
check "curl installed" bash -c 'command -v curl >/dev/null'

section "Licensing"
check "AGPL license included in image" test -s /usr/share/licenses/arch-orb/LICENSE
check "third-party notices included in image" test -s /usr/share/licenses/arch-orb/THIRD_PARTY.md

section "Orb user contract"
if [ "$(id -un)" = "user" ]; then ok "default user is user"; else bad "default user is user ($(id -un))"; fi
if [ "$(id -u)" = "1000" ]; then ok "user uid is 1000"; else bad "user uid is 1000 ($(id -u))"; fi
if getent group user >/dev/null && getent passwd user | grep -q '^user:x:1000:1000:.*:/home/user:'; then
	ok "user group and /home/user home"
else
	bad "user group and /home/user home"
fi
check "HOME is /home/user" test "$HOME" = "/home/user"
check "/home/user is writable" test -w "$HOME"
if [ "$(sudo -n id -u 2>/dev/null)" = "0" ]; then ok "passwordless sudo"; else bad "passwordless sudo"; fi
check "/etc/machine-id is present" test -s /etc/machine-id

section "Package manager and archlinuxcn"
check "archlinuxcn repository configured" bash -c 'grep -q "^\[archlinuxcn\]" /etc/pacman.conf'
check "Arch mirrorlist present" test -s /etc/pacman.d/mirrorlist
check "archlinuxcn mirrorlist present" test -s /etc/pacman.d/archlinuxcn-mirrorlist
check "temporary SigLevel override removed" bash -c '! grep -q "^SigLevel = Never" /etc/pacman.conf'
check "archlinuxcn keyring installed" paru -Q archlinuxcn-keyring
check "paru is available in archlinuxcn" bash -c 'paru -Sl archlinuxcn | grep -q "paru "'
check "paru installed" paru -Q paru
if paru --version 2>/dev/null | grep -q 'paru'; then ok "paru runs"; else bad "paru runs"; fi
if paru -Q google-chrome >/dev/null 2>&1; then
	ok "google-chrome installed from AUR ($(paru -Q google-chrome | awk '{print $2}'))"
else
	bad "google-chrome installed from AUR"
fi
check "google-chrome package is queryable by paru" paru -Q google-chrome

section "Amp CLI"
check "/usr/local/bin/amp exists" test -x /usr/local/bin/amp
if readlink -f /usr/local/bin/amp | grep -q '/home/user/.amp/bin/amp'; then
	ok "amp resolves to the updatable binary"
else
	bad "amp resolves to the updatable binary"
fi
if amp --version 2>/dev/null | grep -qE '^[0-9]'; then ok "amp --version"; else bad "amp --version"; fi
check "amp orb bootstrap is available" bash -c 'amp orb bootstrap --help >/dev/null'
check "amp binary is writable for self-updates" test -w /home/user/.amp/bin/amp
check "amp bin directory is writable" test -w /home/user/.amp/bin
check "amp orb desktop ensure is available" bash -c 'amp orb desktop ensure --help >/dev/null'
check "amp orb service is available" bash -c 'amp orb service --help >/dev/null'
check "agent-browser runs" agent-browser --version

section "Headless systemd units"
check "amp.slice installed" test -s /etc/systemd/system/amp.slice
check "amp-control.slice installed" test -s /etc/systemd/system/amp-control.slice
check "amp-workload.slice installed" test -s /etc/systemd/system/amp-workload.slice
check "amp-headless.service installed" test -s /etc/systemd/system/amp-headless.service
check "amp-headless-bootstrap.service installed" test -s /etc/systemd/system/amp-headless-bootstrap.service
check "amp-headless-env.service installed" test -s /etc/systemd/system/amp-headless-env.service
check "amp-headless-env.path enabled" test -L /etc/systemd/system/multi-user.target.wants/amp-headless-env.path
check "websocat.service enabled" test -L /etc/systemd/system/multi-user.target.wants/websocat.service
check "sshd.service enabled" test -L /etc/systemd/system/multi-user.target.wants/sshd.service
check "websocat.service requires sshd.service" bash -c 'grep -qx "Requires=sshd.service" /etc/systemd/system/websocat.service'
check "sshd stays in amp-control.slice" bash -c 'grep -qx "Slice=amp-control.slice" /etc/systemd/system/sshd.service.d/amp-control.conf'
check "systemd-run at /usr/bin/systemd-run" test -x /usr/bin/systemd-run
check "websocat at /usr/local/bin/websocat" test -x /usr/local/bin/websocat
check "amp-run-workload executable" test -x /usr/local/bin/amp-run-workload
check "amp-headless-update-binary executable" test -x /usr/local/bin/amp-headless-update-binary
check "amp-headless-apply-env executable" test -x /usr/local/bin/amp-headless-apply-env
check "amp-validate-workload-cgroups executable" test -x /usr/local/bin/amp-validate-workload-cgroups
check "sudoers rule for systemd-run" sudo -n test -s /etc/sudoers.d/amp-systemd-run
if [ "$(sudo -n -g root id -gn 2>/dev/null)" = "root" ]; then
	ok "sudo allows any target group"
else
	bad "sudo allows any target group"
fi
check "prepared-headless-release marker present" bash -c 'grep -q "^template " /home/user/.amp/prepared-headless-release 2>/dev/null'
check "no paru AUR clone baked in" test ! -e /home/user/.cache/paru

section "Git and recommended tools"
GIT_VERSION=$(git --version | awk '{print $3}')
if version_at_least "$GIT_VERSION" "2.34"; then
	ok "git >= 2.34 ($GIT_VERSION)"
else
	bad "git >= 2.34 ($GIT_VERSION)"
fi
check "git at /usr/bin/git" test -x /usr/bin/git
check "gh installed" gh --version
check "ripgrep installed" rg --version
check "openssh client installed" ssh -V

section "Additional official-image tools"
check "bun installed" bun --version
check "pnpm installed" pnpm --version
check "yarn installed" yarn --version
check "corepack installed" corepack --version
check "uv installed" uv --version
check "glab installed" glab --version
check "ImageMagick magick installed" magick --version
check "websocat installed" websocat --version
check "vim installed" vim --version
check "Nix installed" nix --version
check "nix-shell installed" nix-shell --version

# This check expands inside bash -c, so the single quotes are intentional.
# shellcheck disable=SC2016
check "Nix single-user layout matches the official image" bash -c '[ "$(stat -c %U /nix)" = user ] && [ "$(stat -c %U /nix/store)" = user ] && [ "$(readlink /usr/local/bin/nix)" = /home/user/.nix-profile/bin/nix ]'

# Signed commit exercises the same ssh-keygen path Amp uses for commit signing.
SIGN_REPO="$TMP_ROOT/git-sign"
mkdir -p "$SIGN_REPO"
if (
	cd "$SIGN_REPO" || exit 1
	git init -q
	git config user.email verify@example.com
	git config user.name Verify
	ssh-keygen -q -t ed25519 -N "" -f "$SIGN_REPO/key"
	git config gpg.format ssh
	git config user.signingkey "$SIGN_REPO/key.pub"
	printf 'signed\n' >file
	git add file
	git commit -q -S -m signed
); then
	ok "git signed commit works"
else
	bad "git signed commit works"
fi
if git clone -q "$SIGN_REPO" "$TMP_ROOT/git-clone"; then
	ok "git clone works"
else
	bad "git clone works"
fi

section "Node.js and Portals requirements"
NODE_VERSION=$(node --version | sed 's/^v//')
if version_at_least "$NODE_VERSION" "18.0.0"; then ok "node >= 18 ($NODE_VERSION)"; else bad "node >= 18 ($NODE_VERSION)"; fi
check "npm installed" npm --version
check "NODE_OPTIONS uses the system CA" test "${NODE_OPTIONS:-}" = "--use-system-ca"
if (
	node -e 'const s = require("http").createServer((q, r) => r.end("portal-ok")); s.listen(0, "127.0.0.1", () => console.log(s.address().port))' >"$TMP_ROOT/node-port" 2>/dev/null &
	node_pid=$!
	for _ in $(seq 1 20); do
		[ -s "$TMP_ROOT/node-port" ] && break
		sleep 0.2
	done
	port=$(head -n1 "$TMP_ROOT/node-port")
	[ -n "$port" ] && curl -fsS "http://127.0.0.1:$port/" | grep -q portal-ok
	result=$?
	kill "$node_pid" 2>/dev/null
	wait "$node_pid" 2>/dev/null
	exit "$result"
); then
	ok "node HTTP server works"
else
	bad "node HTTP server works"
fi
if (
	node -e 'const https = require("https"); const request = https.get("https://static.ampcode.com/cli/cli-version.txt", (response) => { console.log(response.statusCode); response.resume(); process.exit(response.statusCode === 200 ? 0 : 1); }); request.on("error", (error) => { console.error(error.message); process.exit(1); }); setTimeout(() => process.exit(2), 30000);' >"$TMP_ROOT/node-https" 2>&1
	grep -q '^200$' "$TMP_ROOT/node-https"
); then
	ok "node HTTPS with system CA"
else
	bad "node HTTPS with system CA"
	sed 's/^/        /' "$TMP_ROOT/node-https" 2>/dev/null | head -5
fi

section "Terminal requirements"
TMUX_VERSION=$(tmux -V | awk '{print $2}')
if version_at_least "$TMUX_VERSION" "2.9"; then ok "tmux >= 2.9 ($TMUX_VERSION)"; else bad "tmux >= 2.9 ($TMUX_VERSION)"; fi
check "tmux-sync-env helper executable" test -x /usr/local/bin/tmux-sync-env
check "tmux config installed" test -s /home/user/.tmux.conf
if (
	tmux -L "verify-$$" new-session -d -s verify 'printf tmux-ok > '"$TMP_ROOT"'/tmux-ok; sleep 2'
	tmux -L "verify-$$" has-session -t verify
	tmux -L "verify-$$" kill-server
	grep -q tmux-ok "$TMP_ROOT/tmux-ok"
); then
	ok "tmux detached session works"
else
	bad "tmux detached session works"
	tmux -L "verify-$$" kill-server 2>/dev/null || true
fi

section "Desktop requirements"
for binary in \
	/opt/amp-wayland/bin/labwc \
	/opt/amp-wayland/bin/waymote-gateway \
	/opt/amp-wayland/libexec/waymote-streamd \
	/opt/amp-wayland/bin/labnag; do
	check "executable $binary" test -x "$binary"
done
check "gsettings present" bash -c 'command -v gsettings >/dev/null'
check "xsettingsd present" bash -c 'command -v xsettingsd >/dev/null'
check "wlr-randr present" bash -c 'command -v wlr-randr >/dev/null'
check "pulseaudio present" bash -c 'command -v pulseaudio >/dev/null'
check "ffmpeg present" bash -c 'command -v ffmpeg >/dev/null'
check "Xwayland present" bash -c 'command -v Xwayland >/dev/null'
check "dbus-daemon present" bash -c 'command -v dbus-daemon >/dev/null'
check "swaybg present" bash -c 'command -v swaybg >/dev/null'
check "foot present" bash -c 'command -v foot >/dev/null'
check "GTK settings schemas present" bash -c 'gsettings list-schemas | grep -q org.gnome.desktop.interface'
check "DejaVu fonts present" bash -c 'fc-list | grep -qi dejavu'
check "libxml2.so.2 compatibility library present" test -e /opt/amp-wayland/lib/x86_64-linux-gnu/libxml2.so.2
check_no_missing_libs "bundled labwc has all libraries" /opt/amp-wayland/bin/labwc
check_no_missing_libs "bundled labnag has all libraries" /opt/amp-wayland/bin/labnag
check_no_missing_libs "waymote-streamd has all libraries" /opt/amp-wayland/libexec/waymote-streamd
check_no_missing_libs "agent-browser has all libraries" /usr/local/lib/node_modules/agent-browser/bin/agent-browser-linux-x64
check_no_missing_libs "Google Chrome has all libraries" /opt/google/chrome/chrome

# shellcheck disable=SC2016
check "dpkg reports amd64 (Desktop installer check)" bash -c '[ "$(dpkg --print-architecture)" = amd64 ]'
if [ "$(stat -c %a /opt/google/chrome/chrome-sandbox 2>/dev/null)" = "4755" ]; then
	ok "Chrome sandbox is setuid root"
else
	bad "Chrome sandbox is setuid root"
fi
check "google-chrome command present" bash -c 'command -v google-chrome >/dev/null'
check "google-chrome --version" bash -c 'google-chrome --version >/dev/null'

# Start the same headless compositor the Desktop uses, then exercise wlr-randr,
# Xwayland, xsettingsd, and PulseAudio against it.
if (
	export XDG_RUNTIME_DIR="$TMP_ROOT/xdg"
	mkdir -p "$XDG_RUNTIME_DIR"
	chmod 700 "$XDG_RUNTIME_DIR"
	export WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman
	/opt/amp-wayland/bin/labwc >"$TMP_ROOT/labwc.log" 2>&1 &
	labwc_pid=$!
	for _ in $(seq 1 40); do
		[ -S "$XDG_RUNTIME_DIR/wayland-0" ] && break
		sleep 0.2
	done
	[ -S "$XDG_RUNTIME_DIR/wayland-0" ] || exit 1
	export WAYLAND_DISPLAY=wayland-0
	wlr-randr | grep -q HEADLESS-1 || exit 1
	wlr-randr --output HEADLESS-1 --custom-mode 1280x720 >/dev/null 2>&1 || exit 1
	Xwayland :99 -geometry 1280x720 -noreset >"$TMP_ROOT/xwayland.log" 2>&1 &
	xwayland_pid=$!
	for _ in $(seq 1 40); do
		[ -S /tmp/.X11-unix/X99 ] && break
		sleep 0.2
	done
	[ -S /tmp/.X11-unix/X99 ] || exit 1
	DISPLAY=:99 xsettingsd -c /dev/null >"$TMP_ROOT/xsettingsd.log" 2>&1 &
	xsettingsd_pid=$!
	sleep 0.5
	kill -0 "$xsettingsd_pid" 2>/dev/null || exit 1
	mkdir -p "$XDG_RUNTIME_DIR/pulse"
	pulseaudio --daemonize=no --exit-idle-time=-1 \
		--load=module-native-protocol-unix \
		--load='module-null-sink sink_name=verify' >"$TMP_ROOT/pulseaudio.log" 2>&1 &
	pulse_pid=$!
	for _ in $(seq 1 40); do
		[ -S "$XDG_RUNTIME_DIR/pulse/native" ] && break
		sleep 0.2
	done
	[ -S "$XDG_RUNTIME_DIR/pulse/native" ] || exit 1
	pactl info >/dev/null 2>&1 || exit 1
	kill "$xsettingsd_pid" "$xwayland_pid" "$pulse_pid" "$labwc_pid" 2>/dev/null
	wait 2>/dev/null
); then
	ok "Desktop compositor, Xwayland, xsettingsd, and PulseAudio start"
else
	bad "Desktop compositor, Xwayland, xsettingsd, and PulseAudio start"
	sed 's/^/        /' "$TMP_ROOT/labwc.log" "$TMP_ROOT/xwayland.log" "$TMP_ROOT/pulseaudio.log" 2>/dev/null | head -20
fi

# Chrome is launched the way the Desktop launches it: no --no-sandbox flag.
if timeout 30 google-chrome --headless=new --disable-gpu \
	--user-data-dir="$TMP_ROOT/chrome" \
	--dump-dom 'data:text/html,<h1>chrome-ok</h1>' 2>"$TMP_ROOT/chrome.log" | grep -q chrome-ok; then
	ok "Chrome headless with sandbox works"
else
	bad "Chrome headless with sandbox works"
	sed 's/^/        /' "$TMP_ROOT/chrome.log" 2>/dev/null | head -10
fi

section "Shared memory"
SHM_MB=$(df -m /dev/shm | awk 'NR==2 {print $2}')
if [ "${SHM_MB:-0}" -ge 512 ]; then
	ok "/dev/shm >= 512 MB (${SHM_MB} MB)"
else
	bad "/dev/shm >= 512 MB (${SHM_MB:-unknown} MB; run with --shm-size=1g)"
fi

section "Network and CA"
if curl -fsS --max-time 30 -o /dev/null https://static.ampcode.com/cli/cli-version.txt; then
	ok "HTTPS to static.ampcode.com with system CA"
else
	bad "HTTPS to static.ampcode.com with system CA"
fi
if curl -fsS --max-time 30 -o /dev/null https://archlinux.org/; then
	ok "HTTPS to archlinux.org with system CA"
else
	bad "HTTPS to archlinux.org with system CA"
fi
if curl -fsS --max-time 30 -o /dev/null https://ampcode.com/; then
	ok "HTTPS to ampcode.com with system CA"
else
	bad "HTTPS to ampcode.com with system CA"
fi
if curl -sS --max-time 30 -o /dev/null https://tunnel.ampcode.com/; then
	ok "TLS to tunnel.ampcode.com"
else
	bad "TLS to tunnel.ampcode.com"
fi

section "Summary"
printf '  %d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
	exit 1
fi
