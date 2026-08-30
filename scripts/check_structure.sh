#!/usr/bin/env bash
# Verify this repo is installable as a Claude Code plugin marketplace.
#
# The failure this exists to catch is publishing something that parses as a repo but does not work as
# a marketplace: a manifest whose `source` points at a directory that was renamed, a plugin without a
# plugin.json, a SKILL.md whose frontmatter lost its closing delimiter. Every one of those is invisible
# to a reader, invisible to git, and fatal to an installer. A consumer discovers it at install time,
# which is the worst place to discover it.
#
# Deliberately dependency-free (bash + python3 stdlib) so it runs in a pre-commit hook, in CI, and on a
# contributor's machine without a toolchain.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
note() { printf '  %s\n' "$1"; }
bad()  { printf 'FAIL: %s\n' "$1"; fail=1; }

MARKETPLACE=".claude-plugin/marketplace.json"

[ -f "$MARKETPLACE" ] || { bad "$MARKETPLACE is missing; nothing can install this repo"; exit 1; }
[ -f LICENSE ] || bad "LICENSE is missing; a public skills repo without one is not reusable"

python3 - "$MARKETPLACE" <<'PY' || fail=1
import json, os, sys, re

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
        for field in ("name", "description"):
            if not re.search(rf"^{field}:\s*\S", fm, re.M):
                bad(f"{sk} frontmatter has no '{field}'")
        m = re.search(r"^name:\s*(\S+)", fm, re.M)
        if m:
            sname = m.group(1)
            if sname != entry:
                bad(f"{sk} declares name '{sname}' but lives in directory '{entry}'")
            if sname in seen_skill_names:
                bad(f"skill name '{sname}' appears in both '{seen_skill_names[sname]}' and '{name}'")
            seen_skill_names[sname] = name

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
          f"{len(seen_skill_names)} skill(s), all resolvable")
raise SystemExit(rc)
PY

if [ "$fail" -eq 0 ]; then
  note "structure OK"
fi
exit "$fail"
