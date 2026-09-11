#!/usr/bin/env bash
# Gate a commit on everything that makes a skill publishable: structure, spec validity, neutrality.
#
# This merges the former check_structure.sh and check_neutrality.sh into one gate. They were split
# by accident of authorship, not by contract: both are hard, dependency-free checks over the same
# tree, and running one without the other certifies half the property. A skill that resolves but
# names a host is unpublished-but-leaked; a neutral skill that does not resolve is clean-but-broken.
# One script, one verdict.
#
# check_normalized.sh stays separate deliberately. It depends on a pinned formatter that may not be
# installed, so it skips silently when it cannot run. Folding a sometimes-skip into a never-skip
# gate would make the gate's verdict depend on who runs it, which is the ambiguity the vendored
# checker exists to remove.
#
# Deliberately dependency-free (bash + python3 stdlib) so it runs in a pre-commit hook, in CI, and
# on a contributor's machine without a toolchain.
#
# Usage: check_skills.sh [file...]   (no args: walk the whole tree; the pre-commit hook runs it
#                                     with always_run and pass_filenames false)
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
note() { printf '  %s\n' "$1"; }
bad()  { printf 'FAIL: %s\n' "$1"; fail=1; }

MARKETPLACE=".claude-plugin/marketplace.json"

[ -f "$MARKETPLACE" ] || { bad "$MARKETPLACE is missing; nothing can install this repo"; exit 1; }
[ -f LICENSE ] || bad "LICENSE is missing; a public skills repo without one is not reusable"

# Phase 1: structure plus Agent Skills spec validity (agentskills.io/specification).
python3 - "$MARKETPLACE" <<'PY' || fail=1
import json, os, re, sys

mp_path = sys.argv[1]
try:
    mp = json.load(open(mp_path))
except Exception as e:
    print(f"FAIL: {mp_path} is not valid JSON: {e}")
    raise SystemExit(1)

rc = 0
def bad(m):
    global rc
    print(f"FAIL: {m}")
    rc = 1

NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")

for key in ("name", "plugins"):
    if key not in mp:
        bad(f"marketplace.json has no '{key}'")

plugins = mp.get("plugins") or []
if not plugins:
    bad("marketplace.json lists no plugins")

seen_plugin_names = set()
seen_skill_names = {}

for p in plugins:
    name = p.get("name")
    src = p.get("source")
    if not name:
        bad("a plugin entry has no 'name'")
        continue
    if name in seen_plugin_names:
        bad(f"duplicate plugin name '{name}'")
    seen_plugin_names.add(name)
    if not p.get("description"):
        bad(f"plugin '{name}' has no description; it is what a browser sees before installing")
    if not isinstance(src, str):
        bad(f"plugin '{name}' source is not a path (nested sources are not used here)")
        continue

    # The source path must exist. A rename that updates the directory and not the manifest produces a
    # repo that looks fine and installs nothing.
    if not os.path.isdir(src):
        bad(f"plugin '{name}' source '{src}' does not exist")
        continue

    pj = os.path.join(src, ".claude-plugin", "plugin.json")
    if not os.path.isfile(pj):
        bad(f"plugin '{name}' has no {pj}")
    else:
        try:
            pdata = json.load(open(pj))
            if pdata.get("name") != name:
                bad(f"plugin.json name '{pdata.get('name')}' != marketplace name '{name}'")
        except Exception as e:
            bad(f"{pj} is not valid JSON: {e}")

    skills_dir = os.path.join(src, "skills")
    if not os.path.isdir(skills_dir):
        bad(f"plugin '{name}' has no skills/ directory")
        continue

    found = 0
    for entry in sorted(os.listdir(skills_dir)):
        sd = os.path.join(skills_dir, entry)
        if not os.path.isdir(sd):
            continue
        sk = os.path.join(sd, "SKILL.md")
        if not os.path.isfile(sk):
            bad(f"{sd} has no SKILL.md")
            continue
        found += 1
        text = open(sk, encoding="utf-8").read()

        # Frontmatter. A lost closing delimiter silently unregisters the skill: the file still reads
        # as sensible markdown, so nothing about it looks wrong.
        if not text.startswith("---\n"):
            bad(f"{sk} does not open with a '---' frontmatter delimiter")
            continue
        end = text.find("\n---\n", 4)
        if end == -1:
            bad(f"{sk} frontmatter is not closed by '---'")
            continue
        fm = text[4:end]

        # Split the frontmatter into key -> raw value, folding YAML continuation lines (mdformat
        # wraps long values mid-word, so a description routinely spans several physical lines).
        fields = {}
        cur = None
        for line in fm.splitlines():
            m = re.match(r"^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$", line)
            if m:
                cur = m.group(1)
                fields[cur] = m.group(2)
            elif cur is not None:
                fields[cur] += " " + line.strip()
        for field in ("name", "description"):
            if not fields.get(field, "").strip():
                bad(f"{sk} frontmatter has no '{field}'")

        sname = fields.get("name", "").strip()
        if sname:
            if sname != entry:
                bad(f"{sk} declares name '{sname}' but lives in directory '{entry}'")
            if len(sname) > 64 or not NAME_RE.match(sname):
                bad(f"{sk} declares name '{sname}': must be <=64 chars, lowercase "
                    "alphanumeric with single-hyphen separators (Agent Skills spec)")
            if sname in seen_skill_names:
                bad(f"skill name '{sname}' appears in both '{seen_skill_names[sname]}' and '{name}'")
            seen_skill_names[sname] = name

        desc = fields.get("description", "").strip()
        if desc and not (1 <= len(desc) <= 1024):
            bad(f"{sk} description is {len(desc)} chars; the spec allows 1-1024")

        # Evals are a SECOND structural position where a skill's propositions live, and they are
        # load-bearing in the opposite direction: a stale skill misleads a reader, a stale eval
        # CERTIFIES the misleading and would keep rewarding the old behaviour after the skill is
        # fixed. Validate the mechanical parts here; the propositions still need a human read.
        ev = os.path.join(sd, "evals", "evals.json")
        if os.path.isfile(ev):
            try:
                edata = json.load(open(ev))
            except Exception as e:
                bad(f"{ev} is not valid JSON: {e}")
            else:
                rows = edata if isinstance(edata, list) else edata.get("evals") or []
                if not rows:
                    bad(f"{ev} defines no eval cases")
                # skill_name occurs at the TOP LEVEL in the object form and can only be per-row in
                # the list form, so both have to be checked. An earlier version checked only per-row
                # and therefore examined a key that is absent from every real file: green because it
                # inspected nothing, which is indistinguishable from green because all was well.
                names = []
                if isinstance(edata, dict) and edata.get("skill_name"):
                    names.append(edata["skill_name"])
                for r in rows if isinstance(rows, list) else []:
                    if isinstance(r, dict) and r.get("skill_name"):
                        names.append(r["skill_name"])
                if not names:
                    bad(f"{ev} declares no skill_name; a rename cannot be detected without one")
                for sn in names:
                    if sn != entry:
                        bad(f"{ev} declares skill_name '{sn}' but lives under '{entry}'")

    if found == 0:
        bad(f"plugin '{name}' contains no skills")

if rc == 0:
    print(f"  marketplace '{mp.get('name')}': {len(plugins)} plugin(s), "
          f"{len(seen_skill_names)} skill(s), all resolvable and spec-valid")
raise SystemExit(rc)
PY

# Phase 2: neutrality. A published skill must not name a specific repository, organization, or host.
#
# Neutrality is what makes these skills useful outside the repos they came from, and since the repo
# is public it is also a disclosure property: a private identifier committed here is public the
# moment it is pushed, and deleting it later does not unpublish it. That irreversibility is why this
# is a pre-commit gate rather than a report.
#
# Scope is every file under plugins/, not just SKILL.md: a bundled script or reference carrying a
# host name leaks exactly as a SKILL.md line does. Anything genuinely specific to one repository
# belongs in that repository's AGENTS.md, and the skill should defer to it by name. Anything
# specific to a machine belongs in a local, uncommitted instructions file.
#
# Patterns are kept deliberately literal and readable rather than clever: a reader has to be able to
# tell at a glance what is banned and add to it confidently.
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

nfiles=("$@")
if [ ${#nfiles[@]} -eq 0 ]; then
  mapfile -t nfiles < <(find plugins -type f -not -path './.git/*')
fi

for f in "${nfiles[@]}"; do
  [ -f "$f" ] || continue
  case "$f" in plugins/*) ;; *) continue ;; esac
  for p in "${PATTERNS[@]}"; do
    if hits=$(grep -n -iE "$p" "$f"); then
      echo "NEUTRALITY: ${f} contains '${p}'"
      printf '%s\n' "$hits" | sed 's/^/    /'
      fail=1
    fi
  done
done

if [ "$fail" -eq 0 ]; then
  note "skills gate OK: structure, spec, neutrality"
else
  cat >&2 <<'MSG'

A published skill must be resolvable, spec-valid, and neutral.

  repo-specific fact  -> that repository's AGENTS.md, and have the skill defer to it
  machine-specific    -> a local, uncommitted instructions file
  credential name     -> neither; describe what is needed, not what it is called here

Neutrality is a pre-commit gate rather than a report because the repo is public: once pushed,
removing the line later does not unpublish it.
MSG
fi
exit "$fail"
