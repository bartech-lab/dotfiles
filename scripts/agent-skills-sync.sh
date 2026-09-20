#!/usr/bin/env bash
#
# agent-skills-sync -- mirror skills from the Claude app's synced skill bundle
# into the Codex and OMP skill directories.
#
# The Claude app syncs skills into ~/.claude/skills/synced/<hash>/. Codex and
# OMP do not read that directory, so skills there are only visible to Claude
# Code. This script copies each skill (a directory containing SKILL.md) from
# the newest synced bundle to:
#
#   ~/.codex/skills/<name>/     # Codex
#   ~/.agents/skills/<name>/    # OMP (agent provider, native location)
#
# Each target directory is replaced wholesale and tagged with a
# .agent-skills-sync marker. A full run (no name args) also removes tagged
# directories that are no longer present in the bundle.
#
# Nothing this script writes is tracked by any git repository. Skill content
# stays in the private local sync; only this generic script lives in
# dotfiles.
#
# Usage:
#   agent-skills-sync                        # all skills in the newest bundle
#   agent-skills-sync NAME [NAME ...]        # only the named skills
#   agent-skills-sync --dry-run              # print the plan, write nothing
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: agent-skills-sync [--dry-run] [name ...]

Mirror skills from ~/.claude/skills/synced/<bundle> into
  ~/.codex/skills/<name>/
  ~/.agents/skills/<name>/

A full run replaces the target directories and removes stale mirrors.
EOF
}

dry_run=0
if [[ ${1:-} == "--dry-run" ]]; then
  dry_run=1
  shift
fi
names=()
for a in "$@"; do
  names+=("$a")
done

synced_root="${HOME}/.claude/skills/synced"
omp_dir="${HOME}/.agents/skills"
codex_dir="${HOME}/.codex/skills"
marker=".agent-skills-sync"

if [[ ! -d "${synced_root}" ]]; then
  echo "error: no synced skill bundle at ${synced_root}" >&2
  exit 2
fi

# Pick the newest bundle directory (Claude names these <hash>_<hash>).
newest=""
newest_mtime=0
for d in "${synced_root}"/*/; do
  [[ -d "${d%/}" ]] || continue
  m=""
  if m="$(stat -c '%Y' "${d%/}" 2>/dev/null)"; then
    :
  else
    m="$(stat -f '%m' "${d%/}" 2>/dev/null || echo 0)"
  fi
  if [[ -n "${m}" && "${m}" -gt "${newest_mtime}" ]]; then
    newest_mtime="${m}"
    newest="${d%/}"
  fi
done
if [[ -z "${newest}" ]]; then
  echo "error: no skill bundle found under ${synced_root}" >&2
  exit 2
fi

# Collect bundled skills: directories under the bundle with a SKILL.md.
all_skills=()
for d in "${newest}"/*/; do
  [[ -d "${d%/}" && -f "${d%/}SKILL.md" ]] || continue
  all_skills+=("${d%/}")
done
if [[ ${#all_skills[@]} -eq 0 ]]; then
  echo "error: no skills (directories with SKILL.md) in ${newest}" >&2
  exit 2
fi

# Resolve requested names (or all of them) to source paths.
targets=()
if [[ ${#names[@]} -gt 0 ]]; then
  for n in "${names[@]}"; do
    found=""
    for d in "${all_skills[@]}"; do
      [[ "${d##*/}" == "${n}" ]] && { found="${d}"; break; }
    done
    [[ -n "${found}" ]] || { echo "error: skill not in bundle: ${n}" >&2; exit 2; }
    targets+=("${found}")
  done
else
  targets=("${all_skills[@]}")
fi

if [[ ${dry_run} -eq 1 ]]; then
  echo "bundle: ${newest}"
  for d in "${targets[@]}"; do
    echo "would mirror ${d##*/} -> ${omp_dir}/${d##*/} and ${codex_dir}/${d##*/}"
  done
  exit 0
fi

for d in "${targets[@]}"; do
  name="${d##*/}"
  for dest_dir in "${omp_dir}" "${codex_dir}"; do
    dest="${dest_dir}/${name}"
    echo "mirroring ${name} -> ${dest}"
    rm -rf "${dest}"
    cp -R "${d}" "${dest}"
    touch "${dest}/${marker}"
  done
done

if [[ ${#names[@]} -eq 0 ]]; then
  prune_names=""
  for d in "${targets[@]}"; do
    prune_names="${prune_names} ${d##*/}"
  done
  for dest_dir in "${omp_dir}" "${codex_dir}"; do
    for entry in "${dest_dir}"/*/; do
      [[ -d "${entry%/}" ]] || continue
      name="${entry##*/}"
      [[ -f "${entry%/}/${marker}" ]] || continue
      case " ${prune_names} " in
        *" ${name} "*) ;;
        *)
          echo "removing stale mirror ${dest_dir}/${name}"
          rm -rf "${entry%/}"
          ;;
      esac
    done
  done
fi

echo "done: ${#targets[@]} skill(s) mirrored to ${omp_dir} and ${codex_dir}"
echo "note: OMP reads its skill list at session start; start a new OMP session to see new skills."
