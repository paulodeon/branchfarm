# /worktree-status

Shows detailed status for a worktree including PR/MR status.

## Usage

`/worktree-status PROJECT/BRANCH`

Example: `/worktree-status myapp/feature-branch`

## Instructions

1. Parse PROJECT and BRANCH from `$ARGUMENTS`
   - Format is `PROJECT/BRANCH`
   - If missing or malformed, ask for clarification

2. Get basic worktree status:
   ```bash
   branch-env status ${PROJECT}/${BRANCH}
   ```
   - Show port, domain, database status
   - Show tmux session status

3. Read project config to get git_host:
   - Find the `.branchfarm.yml` for the project and check the `git_host` field

4. Check for associated PR/MR:
   - For GitHub (`git_host: github`):
     ```bash
     cd ${WORKTREE_PATH} && gh pr list --head ${BRANCH} --json number,title,state,url
     ```
   - For GitLab (`git_host: gitlab`):
     ```bash
     cd ${WORKTREE_PATH} && glab mr list --source-branch ${BRANCH}
     ```

5. If PR/MR exists, show:
   - PR/MR number and title
   - State (open, merged, closed)
   - URL
   - CI status (if available)

6. Display summary:
   - Worktree path and port
   - Access URL
   - Git branch status (ahead/behind main)
   - PR/MR status and CI results
