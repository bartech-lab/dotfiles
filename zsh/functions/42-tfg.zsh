tfg() {
  emulate -L zsh
  unsetopt XTRACE VERBOSE

  local agent=claude cycles usage='Usage: tfg [--codex] [--ignore-weekly] [--ignore-5h] [cycles]'
  local -a limit_args=()
  while (( $# )); do
    case $1 in
      -h|--help)
        print -r -- $usage
        print -r -- 'Run Tokens for Good cycles in ~/volunteer/tokens-for-good (Claude by default).'
        print -r -- 'Each cycle is a fresh headless session. Without a count it runs until 90% 5h or 95% weekly usage, or Ctrl-C.'
        print -r -- '--ignore-weekly  this run only: skip the 95% weekly stop and run until the weekly limit.'
        print -r -- '--ignore-5h      this run only: skip the 90% 5h stop and run until the 5h limit.'
        print -r -- 'Paid extra usage always stops the run at once.'
        print -r -- 'First run saves your Tokens for Good key in ~/.zshenv (mode 600).'
        return 0 ;;
      --codex) agent=codex ;;
      --ignore-weekly) limit_args+=(--long-limit 100) ;;
      --ignore-5h) limit_args+=(--short-limit 100) ;;
      <1->)
        [[ -z $cycles ]] || { print -u2 -- $usage; return 2 }
        cycles=$1 ;;
      *) print -u2 -- $usage; return 2 ;;
    esac
    shift
  done

  local work_dir="$HOME/volunteer/tokens-for-good"
  if [[ ! -f $work_dir/app/src/mcp-server.js || ! -x $HOME/volunteer/bin/tfg-run ]]; then
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

  local -a run_args=()
  [[ $agent == codex ]] && run_args+=(--codex)
  run_args+=($limit_args)
  [[ -n $cycles ]] && run_args+=($cycles)
  command "$HOME/volunteer/bin/tfg-run" "${run_args[@]}"
}
