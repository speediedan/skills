# Consumer-side tooling

Optional. Nothing here is needed to USE the skills; it exists for repositories that **vendor** them
(copy the files into their own `.claude/skills/`) rather than installing the plugin.

**Vendor the whole skill directory, not just `SKILL.md`.** A skill may bundle `scripts/` and
`references/` that its own instructions refer to by relative path, so a copy of `SKILL.md` alone is a
skill whose every internal reference is broken. That failure is quiet in the worst way: the file that
was copied matches upstream, so a checker comparing only `SKILL.md` reports the copy as current while
a reader following the skill's instructions finds the script it names is absent. Copy the directory,
and delete files upstream removed rather than leaving them, since a stale script beside a current
`SKILL.md` still runs.

## `check_vendored_skills.py`

A pre-commit hook asserting that vendored skills have not been edited locally.

**The problem it solves.** A local edit to a vendored skill is silently discarded the next time the
copy is refreshed from upstream. The person who wrote it loses the work and nobody finds out why. That
is invisible without a check, and unlike "the master has moved ahead", it is something the person who
trips it can act on: send the change upstream instead.

**What it deliberately does not do.** It does not detect that upstream has moved ahead of your copy.
That needs upstream to be available, so it would mean a network call on every commit or a dependency
that fails on a clean clone. A hook that fails on a clean checkout teaches contributors to pass
`--no-verify`, which disables every other hook too, and that trade is not worth making for a condition
a contributor cannot act on anyway.

### Installing

Three pieces, and the guard does nothing until all three are present. A manifest with no hook to read
it is inert, and reads as protection to anyone who finds it.

1. Copy `check_vendored_skills.py` into your repository's `scripts/`.
1. Add the manifest at `.claude/skills/.shared-skills.sha256` (below).
1. Wire the hook:

```yaml
  - repo: local
    hooks:
      - id: vendored-skills-unmodified
        name: Vendored skills are not edited here
        entry: python3 scripts/check_vendored_skills.py
        language: system
        files: ^\.claude/skills/
        pass_filenames: false
```

The manifest lives at `.claude/skills/.shared-skills.sha256` and is `sha256sum`-compatible. It covers
**every vendored file**, not one line per skill: a bundled script edited locally is lost by the next
refresh exactly as a `SKILL.md` edit is, so listing only `SKILL.md` leaves the bulk of a multi-file
skill unguarded.

```
# Vendored from https://github.com/speediedan/skills.
# Regenerated when the vendored copies are refreshed. Do not hand-edit.
<sha256>  .claude/skills/gpu-lease/SKILL.md
<sha256>  .claude/skills/<multi-file-skill>/SKILL.md
<sha256>  .claude/skills/<multi-file-skill>/scripts/<tool>.py
<sha256>  .claude/skills/<multi-file-skill>/references/<doc>.md
```

Generate or refresh it by hashing every file under the **vendored** skill directories, naming them
explicitly:

```bash
for sk in gpu-lease az-pipelines-ops <other-vendored-skill>; do
  find ".claude/skills/$sk" -type f
done | sort | xargs sha256sum
```

**Do not hash everything under `.claude/skills/`.** A consuming repo keeps its own skills there too,
and listing those in the manifest makes the hook refuse legitimate local edits to them - turning a
guard against silent data loss into an obstacle to ordinary work, which is how a hook earns
`--no-verify`. Only the copies that upstream overwrites belong in the manifest.

Better still, have whatever refreshes your copies regenerate it in the same operation, since that
component already knows which skills are vendored. **Regenerating it in the same step that changes the files
is the point:** otherwise every legitimate refresh trips the hook, which is the `--no-verify` training
problem again.

A missing manifest is treated as a failure rather than a skip, deliberately. A skip would be
indistinguishable from a clean pass, which is the ambiguity the check exists to remove.

### Credit

Written by the maintainer of a consuming repository and generalized here so the other consumers do not
each reinvent it.
