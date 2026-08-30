#!/usr/bin/env bash
# Refuse to commit a skill that names a specific repository, organization, or host.
#
# These skills are published. Neutrality is what makes them useful outside the repos they came from,
# and since the repo is public it is also a disclosure property: a private identifier committed here
# is public the moment it is pushed, and deleting it later does not unpublish it. The failure mode is
# therefore not "drift" but "cannot be undone", which is why this is a pre-commit gate rather than a
# report.
#
# Anything genuinely specific to one repository belongs in that repository's AGENTS.md, and the skill
# should defer to it by name. Anything specific to a machine belongs in a local, uncommitted
# instructions file.
#
# Usage: check_neutrality.sh [file...]   (pre-commit passes the staged files)
set -uo pipefail

# Patterns that must never appear in a published skill. Kept deliberately literal and readable rather
# than clever: a reader has to be able to tell at a glance what is banned and add to it confidently.
PATTERNS=(
  # specific repositories and organizations
  'interpretune'
  'finetuning-scheduler'
  'it-interp-engine-adapter'
  'dev\.azure\.com'
  # host and account identifiers
  'az_pipeline_agent'
  'di_leases'
  'speediedl'
  # credentials by name
  'AZURE_DEVOPS_EXT_PAT'
  'CODECOV_TOKEN'
  'HF_TOKEN'
)

rc=0
files=("$@")
if [ ${#files[@]} -eq 0 ]; then
  mapfile -t files < <(find . -name 'SKILL.md' -not -path './.git/*')
fi

for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  case "$f" in
    */skills/*|*SKILL.md) ;;
    *) continue ;;
  esac
  for p in "${PATTERNS[@]}"; do
    if hits=$(grep -n -iE "$p" "$f"); then
      echo "NEUTRALITY: ${f} contains '${p}'"
      printf '%s\n' "$hits" | sed 's/^/    /'
      rc=1
    fi
  done
done

if [ "$rc" -ne 0 ]; then
  cat >&2 <<'MSG'

A published skill must not name a specific repository, organization, or host.

  repo-specific fact  -> that repository's AGENTS.md, and have the skill defer to it
  machine-specific    -> a local, uncommitted instructions file
  credential name     -> neither; describe what is needed, not what it is called here

This is a pre-commit gate rather than a report because the repo is public: once pushed,
removing the line later does not unpublish it.
MSG
fi
exit "$rc"
