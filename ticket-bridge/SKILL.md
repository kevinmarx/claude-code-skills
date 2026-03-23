---
name: ticket-bridge
version: 1.0.0
description: Bridge between ticket systems (Linear, Azure DevOps) and git workflows. Detects ticket refs, formats PR descriptions, and orchestrates ticket-to-branch and PR-to-ticket flows.
---

# ticket-bridge

Connect ticket systems to your git workflow. Detect ticket references, start work from tickets, and create PRs that link back to tickets automatically.

## When to use

- User provides a ticket ID and wants to start working on it
- Creating a PR and need to link tickets in the description
- Need to detect which tickets are associated with the current branch
- Setting up ticket system config for a repo

## Configuration

Always check `.claude/settings.local.json` for existing ticket config before prompting the user. If config is missing and you need it (e.g., to generate URLs), ask the user and offer to persist it.

```bash
# Show current config
bash ~/.claude/skills/ticket-bridge/bridge.sh config --repo .

# Set config
bash ~/.claude/skills/ticket-bridge/bridge.sh config --repo . \
  --set --linear-team groupme --ado-project GroupMe --ado-org nickelgroup
```

## Workflow: Starting work from a ticket

When the user gives a ticket ID (Linear like `GRO-123` or ADO like `AB#12345` / plain number):

1. **Fetch ticket details** via MCP:
   - Linear: call `mcp__plugin_linear-mcp_linear-server__get_issue` with the ticket ID
   - ADO: call `mcp__plugin_azure-devops-mcp_azure-devops-mcp__wit_get_work_item` with the numeric ID and project from config

2. **Create a branch** using worktree-manager:
   - Slugify the ticket title (lowercase, hyphens, max 50 chars)
   - Branch name: `users/kemarx/<ticket-id>-<slugified-title>`
   ```bash
   bash ~/.claude/skills/worktree-manager/worktree.sh new <ticket-id>-<slugified-title>
   ```

3. **Update ticket status**:
   - Linear: call `mcp__plugin_linear-mcp_linear-server__save_issue` with `id` and `state: "started"` (or "In Progress")
   - ADO: call `mcp__plugin_azure-devops-mcp_azure-devops-mcp__wit_update_work_item` to set state to Active

4. **Comment on ticket** with the branch name:
   - Linear: call `mcp__plugin_linear-mcp_linear-server__save_comment` with `issueId` and `body` containing the branch name
   - ADO: call `mcp__plugin_azure-devops-mcp_azure-devops-mcp__wit_add_work_item_comment` with the branch name

## Workflow: Creating a PR

1. **Detect ticket references**:
   ```bash
   bash ~/.claude/skills/ticket-bridge/bridge.sh detect
   ```

2. **Fetch ticket details** via MCP for each detected ref (same calls as above) to get titles and context for the PR description.

3. **Generate PR body**:
   ```bash
   bash ~/.claude/skills/ticket-bridge/bridge.sh format-pr --tickets "GRO-123,AB#456"
   ```

4. **Create the PR** with `gh pr create`, incorporating the generated ticket links section into the PR body.

5. **Link tickets back to the PR**:
   - Linear: call `mcp__plugin_linear-mcp_linear-server__save_comment` on each ticket with the PR URL
   - ADO: call `mcp__plugin_azure-devops-mcp_azure-devops-mcp__wit_link_work_item_to_pull_request` with the repo ID, PR ID, and project ID

## Detecting tickets

```bash
# Auto-detect from branch + last 5 commits
bash ~/.claude/skills/ticket-bridge/bridge.sh detect

# Branch name only
bash ~/.claude/skills/ticket-bridge/bridge.sh detect --branch-only

# From a specific directory
bash ~/.claude/skills/ticket-bridge/bridge.sh detect --path /Users/kemarx/workspace/mai/groupme-ios
```

Output is JSON: `[{"type":"linear","id":"GRO-123"},{"type":"ado","id":"12345"}]`
