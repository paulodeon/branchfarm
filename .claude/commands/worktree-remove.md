# /worktree-remove

Removes a worktree after checking merge status.

## Usage

`/worktree-remove PROJECT/BRANCH`

Example: `/worktree-remove myapp/feature-branch`

## Instructions

1. Parse PROJECT and BRANCH from `$ARGUMENTS`
   - Format is `PROJECT/BRANCH`
   - If missing or malformed, ask for clarification

2. Verify worktree exists:
   ```bash
   branch-env status ${PROJECT}/${BRANCH}
   ```
   - If not found, show error and list available worktrees

3. Read project config to get git_host:
   - Find the `.branchfarm.yml` for the project and check the `git_host` field

4. Check MR/PR merge status:
   - For GitHub (`git_host: github`):
     ```bash
     cd ${WORKTREE_PATH} && gh pr list --state merged --head ${BRANCH}
     ```
   - For GitLab (`git_host: gitlab`):
     ```bash
     cd ${WORKTREE_PATH} && glab mr list --state merged --source-branch ${BRANCH}
     ```

5. If NOT merged:
   - Warn the user: "Branch ${BRANCH} has not been merged yet."
   - Ask for confirmation before proceeding
   - Show option to cancel

6. Remove the worktree:
   ```bash
   branch-env remove ${PROJECT}/${BRANCH}
   ```

7. Confirm cleanup completed:
   - Show what was removed (worktree, database, Caddy config, etc.)
