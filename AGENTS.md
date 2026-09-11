# AGENTS.md

Repository-specific guidance for coding agents working in this dotfiles repo.

This repo is public. Never commit anything that identifies an employer, a
colleague, an internal host, an internal project, or a ticket. Keep such
content in the owning repository's own local `AGENTS.md` instead.

## Scope

- Target platform is macOS 14+ with zsh.
- Prioritize minimal, readable, idempotent shell automation.
- Preserve existing behavior unless the task explicitly requests a behavior change.

## Repository Map

- `zsh/functions/*.zsh` - interactive shell functions and aliases
- `scripts/bin/*` - executable scripts invoked directly
- `scripts/shims/*` - symlinks that shadow real binaries on `PATH` (currently `git`)
- `docs/*.md` - user-facing documentation
- `Brewfile` - Homebrew formula/cask/extensions source of truth
- `discord/openasar/*` - OpenAsar persistence assets (opt-in)

## Function File Numbering

Keep numbered function files stable and intentional.

- `00-*` core shell/plugin setup
- `10-*` shell aliases/replacements
- `20-*` Homebrew helpers
- `21-*` Pacman/yay helpers (Linux, parallel to `20-*`)
- `30-*` git helpers
- `40-*` development utilities
- `50-*` media utilities
- `51-*` yt-dlp download helpers
- `60-*` macOS/system defaults
- `61-69*` desktop app helpers (Discord in `61-discord.zsh`, KDE in `62-kde.zsh`)

Rules:

- Do not pick arbitrary numbers when adding files.
- Place new files in the correct bucket; use the next coherent slot.
- If a renumber would cause churn, keep existing names and document rationale.

## Editing Standards

- Use `set -euo pipefail` in scripts where appropriate.
- Quote paths and arguments defensively (spaces are common on macOS).
- Prefer explicit error messages and non-zero exits on invalid input.
- Provide `--help` for non-trivial scripts.
- Keep machine-specific behavior opt-in (not silently enabled in installer).

## Documentation Requirements

When adding or changing user-facing commands, update docs in the same change:

- `README.md` command lists and docs links
- `docs/functions.md` command reference
- category doc when relevant (for example `docs/dev.md` or `docs/discord-openasar.md`)
- `docs/architecture.md` only when structure/load-order details actually changed

## Validation Checklist

Run the smallest relevant checks before finishing:

- zsh function changes: `source ~/.zshrc` and run affected command(s)
- Bash/POSIX sh changes: run `shellcheck --severity=warning` on changed files selected by their shebang, then keep the relevant `bash -n` or `sh -n` check
- zsh changes: run `zsh -n`; do not pass zsh scripts to ShellCheck, even when they use a `.sh` suffix
- script changes: run `--help` and one realistic invocation
- Keep the relevant integration tests, including `git-auto-pull/tests/test.sh`, `scripts/gitlab-stats/tests/test.sh`, and `node --test scripts/gitlab-reviews/humanReviews.test.mjs` when affected
- Tests must pass with no local config present. Run `HR_CONFIG=/nonexistent node --test scripts/gitlab-reviews/humanReviews.test.mjs` for the gitlab-reviews suite
- Brewfile changes: `brew bundle check --file=~/dotfiles/Brewfile` when practical
- docs changes: verify command names/flags exactly match implementation

## Git Hygiene

- Never revert unrelated local changes.
- Keep commits scoped and message style consistent with repo history (`feat:`, `fix:`, etc.).
- Do not use destructive git operations unless explicitly requested.
