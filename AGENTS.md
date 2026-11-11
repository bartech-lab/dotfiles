# AGENTS.md

Repository-specific guidance for coding agents working in this dotfiles repo.

This repo is public. Never commit anything that identifies an employer, a
colleague, an internal host, an internal project, or a ticket. Keep such
content in the owning repository's own local `AGENTS.md` instead.

## Scope

- Both platforms are in active use: macOS 14+ and Linux (EndeavourOS/Arch), both with zsh.
- Guard platform-specific work with `$DOTFILES_OS`. Never drop a Linux branch as dead code.
- Prioritize minimal, readable, idempotent shell automation.
- Preserve existing behavior unless the task explicitly requests a behavior change.

## Repository Map

- `scripts/shims/*` - symlinks that shadow real binaries on `PATH` (currently `git`)
- `scripts/gitlab-reviews/*` - GitLab review harvester, identities in local config
- `Brewfile` - Homebrew formula/cask/extensions source of truth
- `discord/openasar/*` - OpenAsar persistence assets (opt-in)

A new application config goes in `config/<app>/`, with a `config_symlinks` call in
`install.sh` and a line in the `docs/architecture.md` tree.

`zsh/functions/*.zsh` files are numbered by bucket. Put a new file in the
matching bucket's next free slot; never pick an arbitrary number.

## Documentation Requirements

When adding or changing user-facing commands, update docs in the same change:

- `README.md` command lists and docs links
- `docs/functions.md` command reference
- category doc when relevant (for example `docs/dev.md` or `docs/discord-openasar.md`)
- `docs/architecture.md` only when structure/load-order details actually changed

## Validation Checklist

Run the smallest relevant checks before finishing:

- zsh function changes: `source ~/.zshrc` and run affected command(s)
- script changes: run `--help` and one realistic invocation
- `scripts/bin/dotfiles-test` runs every tracked suite (about 90 s). `.githooks/pre-push` runs it, so a failing suite blocks the push; a new test file named `test.sh`, `test-*.sh`, `test_*.py`, or `*.test.mjs` joins it without any edit
- Run zsh tests as `zsh zsh/tests/run.zsh [test-name...]`, never `zsh zsh/tests/test-*.zsh` directly: the runner adds the timeout
- Tests must pass with no local config present
- Brewfile changes: `brew bundle check --file=~/dotfiles/Brewfile` when practical
- docs changes: verify command names/flags exactly match implementation

## Git Hygiene

- Never revert unrelated local changes.
- Keep commits scoped and message style consistent with repo history (`feat:`, `fix:`, etc.).
- Do not use destructive git operations unless explicitly requested.
