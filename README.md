# skills

Agent skills shared across repositories that run CI on a self-hosted agent pool and share a multi-GPU
host. Written for Claude Code, and deliberately free of anything tying them to one repository, so they
are useful outside the repos they came from.

## What is here

| Plugin | Skill | Covers |
| --- | --- | --- |
| `common-infra-skills` | `gpu-lease` | Serializing GPU work through a host-wide lease: planning around queuing, reserving GPUs for interactive sessions, recovering from stuck or stale leases |
| `common-infra-skills` | `az-pipelines-ops` | Operating a self-hosted Azure DevOps pipeline: telling a gated build from an unauthorized one from a genuinely stuck one, releasing approvals, confirming dispatch |

Both are host-independent. They name no repository, no organization, and no host values, which is
what makes them shareable at all. Anything genuinely specific to one repository belongs in that
repository's `AGENTS.md`, and the skills defer to it by name rather than guessing.

## Two ways to consume them

Pick one deliberately. They differ in who gets the skills, not in what the skills say.

|  | Plugin install | Vendoring |
| --- | --- | --- |
| Who gets them | You, on this machine | Anyone who clones the consuming repo |
| Updates | `/plugin update`, no repo change | A sync step and a commit |
| Invoked as | `common-infra-skills:gpu-lease` | `gpu-lease` |
| Best when | You want them across many repos | A repo's contributors should get them with nothing installed |

They coexist without colliding, because plugin skills are namespaced and vendored ones are bare. The
subtler hazard is that both can be listed and invocable under different names with **different
content**, whenever a vendored copy has fallen behind. That is invisible in a way a collision is not,
which is what the drift check below exists to close.

### Option 1: install as a plugin

```
/plugin marketplace add speediedan/skills
/plugin install common-infra-skills@speediedan-skills
```

Nothing else is needed. Installs are recorded per user rather than per clone, so a colleague cloning
your repository will not have them.

### Option 2: vendor the skills into a repository

Copy the skill directories into the consuming repo's `.claude/skills/`, so they travel with a clone:

```bash
cp -r plugins/common-infra-skills/skills/gpu-lease         /path/to/repo/.claude/skills/
cp -r plugins/common-infra-skills/skills/az-pipelines-ops  /path/to/repo/.claude/skills/
```

Then adopt the drift check below, because a vendored copy is a copy and copies diverge.

## Keeping vendored copies honest

Two different things can go wrong, they need different checks, and the split is by **who can act on
the failure**.

### Someone edited the vendored copy

Actionable by whoever trips it, and it needs nothing but the local files. A local edit to a vendored
skill is silently discarded the next time the copy is refreshed: the person who wrote it loses the
work and nobody finds out why.

`consumer/check_vendored_skills.py` is a pre-commit hook that catches exactly this. To install it:

1. Copy `consumer/check_vendored_skills.py` into the consuming repo, conventionally `scripts/`.

2. Add a manifest at `.claude/skills/.shared-skills.sha256`, in `sha256sum` format:

   ```
   # Vendored from https://github.com/speediedan/skills (plugin: common-infra-skills).
   # Regenerated when the vendored copies are refreshed. Do not hand-edit.
   <sha256>  .claude/skills/gpu-lease/SKILL.md
   <sha256>  .claude/skills/az-pipelines-ops/SKILL.md
   ```

   Generate it with `sha256sum .claude/skills/*/SKILL.md` from the repo root.

3. Wire the hook in `.pre-commit-config.yaml`:

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

**Whatever refreshes the vendored copies must regenerate the manifest in the same operation.** This is
the one requirement that makes the hook work rather than backfire: without it every legitimate refresh
trips the hook, and a hook that fires on correct behavior teaches people to pass `--no-verify`, which
disables every other hook in the repo.

A missing manifest is treated as a failure rather than a skip, deliberately. A skip would be
indistinguishable from a clean pass, which is the ambiguity the check exists to remove.

### Upstream has moved ahead of the vendored copy

Not actionable by a contributor and not detectable offline, so it is deliberately **not** in the
pre-commit hook: that would mean a network call on every commit, or a hook that fails on a clean
clone, which is the `--no-verify` problem again.

Check it when you choose to, by diffing against a clone of this repository:

```bash
diff -r plugins/common-infra-skills/skills/gpu-lease  /path/to/repo/.claude/skills/gpu-lease
```

If you maintain several consuming repos, script that comparison once rather than remembering it. The
useful shape is a `status` mode that reports every consumer's drift in one run, refuses when its own
clone of this repository is stale (otherwise every consumer looks drifted at once, which is a
precondition failure wearing a content failure's costume), and distinguishes formatting-only
differences from real ones.

## Contributing back

If you fix something in a vendored copy, send it here rather than leaving it local. A local fix is
discarded by the next refresh, and every consumer keeps the bug.

Skills in this repository are checked on commit for three things, so an edit that breaks one will be
refused rather than published:

- **Neutrality**: no repository, organization, host, or credential names. This is what makes them
  publishable, and once pushed it cannot be undone, so it is a gate rather than a report.
- **Structure**: the marketplace manifest resolves, every plugin has a `plugin.json` whose name
  agrees, and every `SKILL.md` opens and closes its frontmatter.
- **Normalization**: each `SKILL.md` is a fixed point of `mdformat==0.7.17` with `mdformat-gfm` and
  `mdformat_frontmatter`. At least one consuming repo runs that formatter over its own copy, so an
  unnormalized file here would be rewritten on contact there and re-create drift on every commit.

Run them yourself with `scripts/check_neutrality.sh`, `scripts/check_structure.sh`, and
`scripts/check_normalized.sh`.

## Requirements

`gpu-lease` describes working with a host-wide lease and assumes one exists, with `GPU_LEASE_CMD`
pointing at it. The lease implementation is host and operator infrastructure and is not distributed
here. The skill is a complete no-op when `GPU_LEASE_CMD` is unset, so installing it on a machine
without a lease costs nothing.

`az-pipelines-ops` assumes an Azure DevOps project and a self-hosted agent pool. Its commands are
parameterized on `${ORG}` and `${PROJECT}`; supply those from your own repository's `AGENTS.md`.

## Licence

Apache-2.0. See `LICENSE`.
