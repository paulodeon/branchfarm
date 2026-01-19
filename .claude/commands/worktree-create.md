# /worktree-create

Creates a new worktree via branch-env.

## Usage

`/worktree-create PROJECT/BRANCH`

Example: `/worktree-create myapp/feature-branch`

## Instructions

1. Parse PROJECT and BRANCH from the argument `$ARGUMENTS`
   - Format is `PROJECT/BRANCH` (e.g., `myapp/feature-branch`)
   - If argument is missing or malformed, ask the user for clarification

2. Create the worktree:
   ```bash
   branch-env create ${PROJECT}/${BRANCH}
   ```

4. After creation, display the summary output from the CLI (it prints a "Ready for development!" block with worktree path, URL, port, and useful commands).
