#!/usr/bin/env bash
# Refuse to commit a SKILL.md that is not a fixed point of the formatter it is normalized against.
#
# WHY THIS EXISTS. Consuming repositories vendor these files verbatim, and at least one runs mdformat
# over its own copy. If the stored form here is not that formatter's output, the consumer's pre-commit
# rewrites the file on contact, which re-creates drift on every commit that touches it, permanently.
#
# That was a convention enforced by a comment in another repository's sync script, which is to say not
# enforced at all: a section was added here without re-running the normalizer, the master was
# published unnormalized, and a consumer discovered it when their hook rewrote the file. The
# normalization requirement had been recorded, verified once, and then quietly depended on for weeks.
#
# It also broke a diagnostic elsewhere that assumed only the CONSUMER could move out of normalized
# form. Once the master can regress, "the consumer's pin changed" stops being the only explanation,
# and a check here is what keeps that assumption true.
#
# Deliberately skips silently when the pinned formatter cannot be run, rather than failing. A
# contributor without network access or uvx should not be blocked from committing prose, and a hook
# that fails on a clean checkout teaches people to pass --no-verify, which disables every other hook.
# The cost of skipping is that normalization is checked by whoever can run it; the cost of failing
# closed is that nobody runs any hook.
set -uo pipefail
cd "$(dirname "$0")/.."

PIN="mdformat==0.7.17"
PLUGINS=(--with mdformat-gfm --with mdformat_frontmatter)

command -v uvx >/dev/null 2>&1 || UVX="$(ls -d /mnt/cache/*/.venvs/*/bin/uvx 2>/dev/null | head -1)"
UVX="${UVX:-uvx}"
command -v "$UVX" >/dev/null 2>&1 || {
  echo "  normalization UNCHECKED: no uvx available (skipping, not failing)"
  exit 0
}

rc=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

files=("$@")
if [ ${#files[@]} -eq 0 ]; then
  mapfile -t files < <(find plugins -name 'SKILL.md' -not -path './.git/*')
fi

for f in "${files[@]}"; do
  case "$f" in *SKILL.md) ;; *) continue ;; esac
  [ -f "$f" ] || continue
  cp "$f" "$tmp/candidate.md"
  if ! timeout 240 "$UVX" --from "$PIN" "${PLUGINS[@]}" mdformat "$tmp/candidate.md" >/dev/null 2>&1; then
    echo "  normalization UNCHECKED for ${f}: formatter did not run (skipping, not failing)"
    continue
  fi
  if ! diff -q "$f" "$tmp/candidate.md" >/dev/null 2>&1; then
    echo "NOT NORMALIZED: ${f}"
    diff "$f" "$tmp/candidate.md" | sed 's/^/    /' | head -20
    rc=1
  fi
done

if [ "$rc" -ne 0 ]; then
  cat >&2 <<MSG

A published skill must be a fixed point of ${PIN} with mdformat-gfm and mdformat_frontmatter.
Consumers vendor these files verbatim and at least one reformats on commit, so an unnormalized
master re-creates drift in that repo on every commit that touches the file.

Fix:
  uvx --from '${PIN}' --with mdformat-gfm --with mdformat_frontmatter mdformat <file>

Ordered lists are the usual cause: mdformat renumbers 1./2./3. to a repeated 1. and inserts a blank
line between items, so adding a numbered list is the edit most likely to trip this.
MSG
fi
exit "$rc"
