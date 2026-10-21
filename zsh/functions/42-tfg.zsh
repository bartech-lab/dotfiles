tfg() {
  emulate -L zsh
  unsetopt XTRACE VERBOSE

  local agent=claude cycles=1
  if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    print -r -- 'Usage: tfg [--codex] [cycles]'
    print -r -- 'Run Tokens for Good cycles in ~/volunteer/tokens-for-good (Claude by default).'
    print -r -- 'First run saves your Tokens for Good key in ~/.zshenv (mode 600).'
    return 0
  fi
  if [[ ${1:-} == --codex ]]; then
    agent=codex
    shift
  fi
  if (( $# > 1 )) || [[ -n ${1:-} && $1 != <1-> ]]; then
    print -u2 -- 'Usage: tfg [--codex] [cycles]'
    return 2
  fi
  cycles=${1:-1}

  local work_dir="$HOME/volunteer/tokens-for-good"
  if [[ ! -f $work_dir/app/src/mcp-server.js ]]; then
    print -u2 -- "tfg: $work_dir is not set up."
    return 1
  fi
  if ! (( $+commands[$agent] )); then
    print -u2 -- "tfg: $agent is not installed or is missing from PATH."
    return 1
  fi

  if [[ -z ${TFG_API_KEY:-} ]]; then
    if [[ ! -t 0 ]]; then
      print -u2 -- 'tfg: Run in a terminal to enter your Tokens for Good key.'
      return 1
    fi
    read -rs 'TFG_API_KEY?Paste your Tokens for Good key (hidden; saved in ~/.zshenv): ' || return 1
    print
    if [[ -z $TFG_API_KEY || $TFG_API_KEY == *[[:space:]]* ]]; then
      unset TFG_API_KEY
      print -u2 -- 'tfg: Enter a nonempty key without whitespace.'
      return 1
    fi
    (umask 077; touch "$HOME/.zshenv") && chmod 600 "$HOME/.zshenv" || return 1
    print -r -- "" "export TFG_API_KEY=${(qq)TFG_API_KEY}" >> "$HOME/.zshenv" || return 1
  fi
  export TFG_API_KEY

  if [[ $agent == claude ]]; then
    ( cd "$work_dir" && command claude "/tfg $cycles" )
  else
    command codex --no-daemon --search --cd "$work_dir" \
      -c "mcp_servers.tfg.command=\"node\"" \
      -c "mcp_servers.tfg.args=[\"$work_dir/app/src/mcp-server.js\"]" \
      -c 'mcp_servers.tfg.env_vars=["TFG_API_KEY"]' \
      -c 'mcp_servers.tfg.disabled_tools=["list_agents","create_agent","rotate_agent_key","revoke_agent","setup_automation","setup_guide","mark_setup_complete","snooze","set_role_preference"]' \
      "Run $cycles Tokens for Good cycles following AGENTS.md and .claude/commands/tfg.md in this folder."
  fi
}
