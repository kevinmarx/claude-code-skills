---
name: architecture-changelog
version: 1.0.0
description: Detect architectural changes (dependencies, config, CI, testing, database) in staged or recent commits and draft CLAUDE.md updates for review.
---

# architecture-changelog

Detect when implementation work has changed the project's architecture and keep the repo's CLAUDE.md accurate.

## When to Use

Run this **after completing implementation work**, before committing or opening a PR. This catches changes to dependencies, config, CI pipelines, test setup, and database schemas that should be reflected in the project documentation.

## Workflow

1. Run the detection script on staged changes:

```bash
bash ~/.claude/skills/architecture-changelog/detect.sh --staged --path /path/to/repo
```

Or scan recent commits:

```bash
bash ~/.claude/skills/architecture-changelog/detect.sh --commits 3 --path /path/to/repo
```

2. Parse the JSON output. If the array is empty, no architectural changes were detected — stop here.

3. If changes were found, analyze what they mean for the project:
   - **dependencies**: New libraries, removed packages, version bumps that change capabilities
   - **config**: Build tool changes, new environment variables, container setup changes
   - **ci**: Pipeline changes, new workflows, deployment config
   - **testing**: New test framework, changed test configuration, test directory structure
   - **database**: New migrations, schema changes, ORM config updates

4. Read the repo's existing `CLAUDE.md` and draft an update that reflects the detected changes. Only add or modify sections relevant to the changes — do not rewrite unrelated content.

5. **Present the draft to the user for review.** Do NOT auto-commit or auto-write the changes. The user decides whether to accept, modify, or skip the update.

6. If no `CLAUDE.md` exists in the repo, offer to create one with the relevant architectural context. Still require user approval before writing.
