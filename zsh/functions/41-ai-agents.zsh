# AI agent CLIs run inside the memory-capped ai-agents.slice cgroup.
# Guard against the failure mode of 2026-09-08: a burst of parallel codex
# background workers reached 51 GB combined and the kernel OOM-killer took
# out the desktop browsers.
# Limits live in ~/.config/systemd/user/ai-agents.slice.
# Install with ai-agent-limits/setup.sh; see ai-agent-limits/README.md.
# Set AI_AGENT_NO_SCOPE=1 to bypass for one shell.

if [[ "$DOTFILES_OS" == linux ]] && (( ${+commands[systemd-run]} )); then
  _ai_agent_scoped() {
    local bin=$1
    shift
    if [[ -n "$AI_AGENT_NO_SCOPE" ]]; then
      command "$bin" "$@"
      return
    fi
    ai-agent-scope "$bin" "$@"
  }

  claude() { _ai_agent_scoped claude "$@" }
  codex()  { _ai_agent_scoped codex "$@" }

  ai-agent-mem() {
    local cg=/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/ai.slice/ai-agents.slice
    if [[ ! -d $cg ]]; then
      print "ai-agents.slice: no agent process running"
      return
    fi
    printf 'current  %s\n' "$(numfmt --to=iec < $cg/memory.current)"
    printf 'high     %s\n' "$(numfmt --to=iec < $cg/memory.high)"
    printf 'max      %s\n' "$(numfmt --to=iec < $cg/memory.max)"
    printf 'throttle events\n'
    grep -E '^(high|max|oom|oom_kill) ' $cg/memory.events
  }
fi
