# ai-agent-limits

Caps the total memory an AI agent session tree can use, so a parallel fan-out
cannot trigger a system-wide OOM kill. Linux only: it relies on cgroup v2.

## Why

On 2026-09-08 a burst of 17 detached `codex-companion.mjs` node workers reached
3.03 GB resident each, 51.4 GB combined, on a 60 GB machine. The kernel
OOM-killer fired three times and killed Chromium, Brave, and electron-mail.
Two forced reboots followed.

Each `--background` codex task spawns its own detached node worker that holds
the whole codex event stream in RAM. Nothing bounded how many ran at once, and
nothing bounded their combined footprint.

## Mechanism

| Piece | Role |
|-------|------|
| `ai-agents.slice` | systemd user slice carrying `MemoryHigh=20G`, `MemoryMax=28G`, `MemorySwapMax=0` |
| `ai-agent-scope` | launcher that starts an agent CLI in a transient scope inside that slice |
| `claude` / `codex` shell functions | route the CLIs through the launcher (`zsh/functions/41-ai-agents.zsh`) |
| `ai-agent-mem` shell function | reports current slice usage and throttle/OOM counters |

`MemoryHigh` throttles the slice and forces reclaim at 20 GiB. `MemoryMax` is
the hard ceiling: at 28 GiB the kernel kills a process inside the slice instead
of picking a victim across the whole machine. Roughly 32 GiB stays reserved for
the desktop.

Descendants inherit the cgroup, so subagents, detached codex workers, and MCP
servers all count against one aggregate limit. This is the property a
per-process `NODE_OPTIONS=--max-old-space-size` cap does not give.

## Install

```sh
~/dotfiles/ai-agent-limits/setup.sh
```

Idempotent. Existing agent sessions keep running outside the slice; restart
them to pick up the cap.

## Verify

```sh
ai-agent-mem
```

`oom_kill` above zero means the slice hit its ceiling and killed an agent
process. That is the guard working: the desktop survived.

## Tuning

Edit `ai-agents.slice`, then re-run `setup.sh`. Keep `MemoryMax` at least
20 GiB below total RAM so the desktop always has headroom.

## Bypass

```sh
AI_AGENT_NO_SCOPE=1 claude
```

## Uninstall

```sh
rm ~/.config/systemd/user/ai-agents.slice ~/.local/bin/ai-agent-scope
systemctl --user daemon-reload
```

Also remove `zsh/functions/41-ai-agents.zsh`.

## Related

`~/.claude/rules/codex-delegation.md` caps concurrent codex jobs at 3 and
requires staged waves. That policy limits how many workers start; this slice
limits what they can consume if the policy is ignored.
