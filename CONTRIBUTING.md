# Contributing to bookshelf-in-a-box

Thanks for wanting to help! 🎉 This project exists to make self-hosting an ebook
library **painless for complete beginners**, so contributions that improve
clarity, reliability, and the first-run experience are especially valued.

## Ways to contribute

- **Report a bug** — use the *Bug report* issue template.
- **Ask for setup help / report a rough edge** — use the *Setup help* issue
  template. Confusing steps are bugs too!
- **Improve the docs** — typo fixes, clearer wording, and better troubleshooting
  entries are all welcome and easy first PRs.
- **Improve the scripts** — more robust OS/architecture handling, better error
  messages, additional platforms.

## Ground rules

This is an **opinionated wrapper** around
[Calibre-Web Automated](https://github.com/crocodilestick/Calibre-Web-Automated).
We deliberately keep it small:

- **Docker is the only host dependency.** No Node, no Python, no extra runtimes
  on the user's machine. Scripts are POSIX shell (`bash`) and PowerShell only.
- **Never break existing users' data.** Anything that touches `data/` must be
  non-destructive.
- **Every script must be idempotent** — safe to run twice — and must fail with a
  friendly, human-readable message rather than a stack trace.
- **Bugs in the ebook server itself** belong
  [upstream](https://github.com/crocodilestick/Calibre-Web-Automated/issues).
  Issues about *setup, wrapping, and docs* belong here.

## Developing & testing your change

Before opening a pull request, please run the same checks our CI runs:

```bash
# 1. Lint the shell scripts (https://www.shellcheck.net/)
shellcheck setup.sh scripts/*.sh

# 2. Validate the Docker Compose file
cp .env.example .env
docker compose config
rm .env

# 3. Sanity-check syntax without executing
bash -n setup.sh scripts/backup.sh scripts/update.sh
```

If you changed `setup.sh` / `setup.ps1`, please test a **fresh run** (delete
`.env` and the `data/` folder in a scratch copy) *and* a **re-run** (run it a
second time) to confirm idempotency.

## Pull request checklist

- [ ] Scripts pass `shellcheck` with no new warnings.
- [ ] `docker compose config` succeeds.
- [ ] Changes are non-destructive to existing `data/`.
- [ ] Docs updated if behaviour changed.
- [ ] Commit messages are clear and descriptive.

## Code of conduct

Be kind and patient — a lot of our users are trying self-hosting for the very
first time. Assume good faith and explain things simply.

## License

By contributing, you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
