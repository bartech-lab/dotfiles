tfg() {
  emulate -L zsh
  unsetopt XTRACE VERBOSE

  if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    print -r -- 'Usage: tfg'
    print -r -- 'Research one nonprofit in Codex; review the report before submission.'
    print -r -- 'First run saves your Tokens for Good key in ~/.zshenv (mode 600).'
    return 0
  fi
  if (( $# )); then
    print -u2 -- 'Usage: tfg'
    return 2
  fi
  if ! (( $+commands[codex] )); then
    print -u2 -- 'tfg: Codex CLI is not installed or is missing from PATH.'
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

  local work_dir="$HOME/logbook/Projects/tokens-for-good"
  mkdir -p "$work_dir" || return 1
  command codex --no-daemon --search --cd "$work_dir" \
    -c 'mcp_servers.tokens-for-good.url="https://tokensforgood.ai/mcp"' \
    -c 'mcp_servers.tokens-for-good.env_http_headers={"X-TFG-Api-Key"="TFG_API_KEY"}' \
    'Use Tokens for Good to research exactly one nonprofit following its methodology. Show me the completed report before submitting it. Do not schedule recurring work.'
}
