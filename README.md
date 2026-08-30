# skills

Agent skills shared across repositories that run CI on a self-hosted agent pool and share a
multi-GPU host. Written for Claude Code, and deliberately free of anything tying them to one
repository, so they are useful outside the repos they came from.

## Plugins

| Plugin | Contents |
| --- | --- |
| `common-infra-skills` | `gpu-lease`: serializing GPU work through a host-wide lease |

## Installing

```
/plugin marketplace add speediedan/skills
/plugin install common-infra-skills@speediedan-skills
```

## Or vendor the skills instead

The skills are plain files, so a repository can also copy them into its own `.claude/skills/`. That
makes them available to anyone who clones that repository without installing anything, which a plugin
install does not do: plugin installs are recorded per user, not per clone.

Both modes can be live at once. Plugin-provided skills are namespaced (`common-infra-skills:gpu-lease`)
while vendored ones are bare (`gpu-lease`), so they are separately addressable rather than colliding.
The cost is that a vendored copy can silently fall behind this repository while presenting the same
name, so if you vendor, diff against upstream as part of your normal checks rather than assuming.

## What these skills deliberately do not contain

They carry no host values, no organization or project identifiers, and no repository names. A skill
that names your build system is not shareable, and a skill that names your host is not portable.

That is a real constraint rather than a stylistic one, and it means each consuming repository has to
supply a few facts of its own. The skills say where to look rather than guessing: they defer to the
consuming repository's `AGENTS.md`. For `gpu-lease` that is whether the repository has a test harness
which self re-execs under the lease, and what its CI jobs tag the lease with.

Anything genuinely specific to a machine (an agent's install directory or uid, RAM, GPU models, a
lease directory path) belongs in a local, uncommitted instructions file rather than in a skill or in
`AGENTS.md`.

## Requirements

`gpu-lease` describes how to work with a host-wide lease. It assumes such a lease exists and that
`GPU_LEASE_CMD` points at it. The lease implementation itself is host and operator infrastructure and
is not distributed here. The skill is a complete no-op when `GPU_LEASE_CMD` is unset, so installing it
on a machine without a lease costs nothing.

## Licence

Apache-2.0. See `LICENSE`.
