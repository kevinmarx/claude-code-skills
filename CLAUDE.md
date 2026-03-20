# CLAUDE.md

## What is this repo?

A collection of [Claude Code skills](https://docs.anthropic.com/en/docs/claude-code/skills) — small, self-contained tools that Claude Code discovers and uses automatically.

## Repo structure

```
<skill-name>/
  SKILL.md       # Required. Skill definition (frontmatter + instructions for Claude)
  README.md      # Required. Human-readable docs (install, usage, how it works)
  set-title.sh   # Scripts/code the skill uses
```

## Rules

- Every skill directory **must** have both a `SKILL.md` and a `README.md`
- `SKILL.md` is for Claude (frontmatter with name/version/description, then usage instructions)
- `README.md` is for humans (problem, solution, install steps, how it works)
- Skills should be minimal — one script, one purpose
- Scripts should output minimal text (Claude parses the output)
- The top-level `README.md` should list all available skills

## Adding a new skill

1. Create a directory named after the skill
2. Add `SKILL.md` with frontmatter (`name`, `version`, `description`) and Claude-facing instructions
3. Add `README.md` with human-facing documentation
4. Add any scripts the skill needs
5. Update the top-level `README.md` to list the new skill

## Install

Copy any skill directory into `~/.claude/skills/`:

```bash
cp -r <skill-name> ~/.claude/skills/<skill-name>
```

Claude Code auto-discovers skills in that directory.
