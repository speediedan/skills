# Consumer-side tooling

Optional. Nothing here is needed to USE the skills; it exists for repositories that **vendor** them
(copy the files into their own `.claude/skills/`) rather than installing the plugin.

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

Copy the script into your repository, add a manifest, and wire the hook:

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

The manifest lives at `.claude/skills/.shared-skills.sha256` and is `sha256sum`-compatible:

```
# Vendored from https://github.com/speediedan/skills (plugin: common-infra-skills).
# Regenerated when the vendored copies are refreshed. Do not hand-edit.
<sha256>  .claude/skills/gpu-lease/SKILL.md
```

Generate or refresh it with `sha256sum .claude/skills/*/SKILL.md`, or have whatever refreshes your
copies regenerate it in the same operation. **Regenerating it in the same step that changes the files
is the point:** otherwise every legitimate refresh trips the hook, which is the `--no-verify` training
problem again.

A missing manifest is treated as a failure rather than a skip, deliberately. A skip would be
indistinguishable from a clean pass, which is the ambiguity the check exists to remove.

### Credit

Written by the maintainer of a consuming repository and generalized here so the other consumers do not
each reinvent it.
