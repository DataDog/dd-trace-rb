# Mirror Community Pull Request Workflow

## Overview

This GitHub Action automatically mirrors community pull requests from external contributors to a new branch in the main DataDog/dd-trace-rb repository. This allows running CI checks with maintainer permissions when contributors haven't enabled "Allow edits by maintainers". The workflow creates a mirror branch named `community-pr-<number>` and an associated pull request with the prefix `[IGNORE] 🪞`.

## Usage

### Comment Trigger (Recommended)

Comment on any pull request with one of the following commands:

```
/mirror
```

Creates an exact mirror that preserves original commits and signatures.

```
/mirror-rebase
```

Creates a rebased mirror by cherry-picking commits onto the target branch.

The workflow will:
1. Fetch the PR branch from the contributor's fork
2. Create or update the `community-pr-<number>` branch
3. Create or update the mirror PR with `[IGNORE] 🪞` prefix
4. Comment back with the mirror PR link

**Permissions**: Only repository maintainers and collaborators can trigger the workflow via comments.

### Manual Trigger

You can also manually trigger the workflow from the Actions tab:

1. Go to **Actions** → **Mirror Community Pull Request**
2. Click **Run workflow**
3. Enter the PR number
4. Optionally check "Rebase and re-sign commits"
5. Click **Run workflow**

## Mirror Modes

### Exact Mirror (Default)

Preserves the exact commits from the contributor's PR, including original commit SHAs and signatures. This is the recommended mode for most cases.

**Use when:**
- You want to test the contributor's exact commits
- Preserving commit history and signatures is important
- The PR branch is up to date with the target branch

### Rebase Mode

Cherry-picks each commit from the PR onto the target branch, creating new commits signed by github-actions[bot]. This is useful when you need to resolve conflicts with the target branch.

**Use when:**
- The PR has conflicts with the target branch
- You need commits rebased onto the latest target branch
- You want all commits signed by the maintainer account

## Updating Mirrors

Re-running `/mirror` or `/mirror-rebase` on the same PR will:
- Force push to the existing `community-pr-<number>` branch with updated commits
- Update the mirror PR title and description
- Sync labels from the original PR
- Comment on the original PR with confirmation

This allows you to refresh the mirror when:
- The original PR receives new commits
- You need to re-run CI checks
- You want to switch between exact and rebase modes
- The original PR metadata changed (title, labels)

## Mirror PR Format

The mirror PR will have:
- **Title**: `[IGNORE] 🪞 #<number> - <original title>`
- **Labels**: Copied from the original PR
- **Description**: Links to original PR, author, branch, and mirror type
- **Close keyword**: `Closes #<number>` to link the PRs

## Examples

```
# Mirror PR #123 with exact commits
/mirror

# Mirror PR #123 and rebase onto master
/mirror-rebase

# The workflow handles repeated runs automatically
/mirror         # First run - creates mirror PR #456
# ... original PR gets new commits ...
/mirror         # Second run - updates mirror PR #456
```

## Troubleshooting

### "Only maintainers and collaborators can use the /mirror command"

You don't have write permissions to the repository. Only maintainers can create mirrors.

### "No commits found in PR"

The PR may be empty or the fork repository may be inaccessible. Verify the PR exists and has commits.

### "Failed to cherry-pick commit"

In rebase mode, the workflow couldn't cleanly cherry-pick a commit. This usually means there are merge conflicts with the target branch. You may need to:
- Use exact mirror mode (`/mirror`) instead
- Ask the contributor to rebase their PR
- Manually resolve conflicts

### Workflow doesn't trigger

Ensure:
- Your comment is exactly `/mirror` or `/mirror-rebase` (case-sensitive)
- You're commenting on a pull request, not an issue
- The PR is in the correct repository
- You have write permissions to the repository
