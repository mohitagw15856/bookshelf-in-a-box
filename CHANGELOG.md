# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
aims to follow [Semantic Versioning](https://semver.org/).

To cut a release: bump `VERSION`, add a section below, then
`git tag vX.Y.Z && git push origin vX.Y.Z` — the Release workflow does the rest.

## [Unreleased]

## [0.3.0] — 2026-07-29
### Added
- **`bookshelf doctor`** — diagnoses common setup problems (Docker, ports,
  permissions, disk, WSL paths, container health) and prints the fix for each.
- **Off-site backups** (`scripts/offsite.sh` + `docker-compose.offsite.yml`) —
  mirror `./backups` to any rclone cloud remote, encrypted if you use a crypt remote.
- **Notifications** (`scripts/notify.sh`) — ntfy / Discord / Slack / Telegram /
  webhook alerts; wired into backups.
- **Send-to-Kindle helper** (`scripts/kindle-setup.sh`) — collects SMTP details
  and sends a real test email before you touch the UI.
- **Import existing collections** (`scripts/import-calibre.sh`) — copy a folder
  of ebooks into ingest, or adopt an existing Calibre library wholesale.
- **Library stats** (`scripts/stats.sh`) — counts, formats, top authors, plus a
  shareable `data/stats.html`.
- **Self-hosted KOReader sync** (`docker-compose.sync.yml`) and Kobo-sync docs.
- **Automatic updates** (`docker-compose.watchtower.yml`) — scoped to bookshelf,
  safest alongside nightly backups.
- **Run as a service** (`scripts/install-service.sh` + `system/bookshelf.service`) —
  systemd unit for headless servers and Raspberry Pis.
- **Release automation** — `VERSION`, this changelog, and a tag-triggered
  Release workflow; version is shown in `status` and `doctor`.

## [0.2.0] — 2026-07-29
### Added
- Interactive **GitHub Pages demo** of the library UI, deployed from `docs/`.
- **`bin/bookshelf` CLI** and a **Makefile** wrapping everyday commands.
- **First-run web wizard** (`web/welcome.html`) with a dependency-free,
  verified **QR generator** (`web/qr.js`) for phone/e-reader pairing.
- **Starter library** (`scripts/seed-library.sh`) — free public-domain books.
- Optional overlays: **Tailscale** (read from anywhere), **Caddy** (HTTPS),
  and **nightly backups**.
- **`scripts/status.sh`** and **`scripts/restore.sh`** (with pre-restore snapshot).
- Real CWA options surfaced in `.env` (`CWA_WATCH_MODE`, `HARDCOVER_TOKEN`).
- Stronger CI (overlay validation, QR check, container smoke test) + Dependabot.

## [0.1.0] — 2026-07-29
### Added
- Initial release: opinionated, beginner-proof wrapper around the
  Calibre-Web Automated Docker image.
- `docker-compose.yml`, `.env.example`, interactive `setup.sh` / `setup.ps1`.
- `scripts/backup.sh`, `scripts/update.sh`.
- Beginner-focused README, MIT license, CONTRIBUTING, issue templates, CI.

[Unreleased]: https://github.com/mohitagw15856/bookshelf-in-a-box/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/mohitagw15856/bookshelf-in-a-box/releases/tag/v0.3.0
[0.2.0]: https://github.com/mohitagw15856/bookshelf-in-a-box/releases/tag/v0.2.0
[0.1.0]: https://github.com/mohitagw15856/bookshelf-in-a-box/releases/tag/v0.1.0
