# Third-party notices

The source code in this repository is licensed under
AGPL-3.0-or-later (see `LICENSE`). The built image also contains the
third-party components below. Their own licenses and terms apply; the AGPL
does not relicense them.

| Component | License or terms | Source / notice |
| --- | --- | --- |
| Google Chrome | Proprietary (`custom:chrome`), Google Chrome Terms of Service | <https://www.google.com/chrome> ; EULA at `/usr/share/licenses/google-chrome/eula_text.html` |
| Amp CLI | Amp License Terms; no separate open-source license found | <https://ampcode.com/terms> |
| `tmux-sync-env` | Amp helper; no separate license found | Copied from Amp's published orb image |
| `agent-browser` | Apache-2.0 | <https://github.com/vercel-labs/agent-browser> ; license copied to `/usr/local/lib/node_modules/agent-browser/LICENSE` |
| `labwc` and `labnag` | GPL-2.0-only | <https://github.com/labwc/labwc> |
| `waymote-gateway` and `waymote-streamd` | MIT (Copyright (c) 2026 Tim Culverhouse) | Copied from Amp's published orb image |
| `paru` | GPL-3.0-or-later | <https://github.com/Morganamilo/paru> |
| Nix and the Nix store | LGPL-2.1 for Nix; each store path keeps its own license | <https://github.com/NixOS/nix> |
| Arch Linux packages | Mixed GPL, LGPL, MIT, BSD, and other licenses | Package licenses under `/usr/share/licenses`; source packages from Arch Linux |
| libxml2 and ICU compatibility libraries (pinned from the Arch archive) | MIT / Unicode | <https://archive.archlinux.org> |
| DejaVu, Liberation, and Adwaita fonts/icons | Bitstream Vera, SIL OFL, and their respective icon licenses | Upstream font/icon projects |

Chrome and Amp components are included for personal use and are not covered by
the AGPL. Check their terms before redistributing the built image.
