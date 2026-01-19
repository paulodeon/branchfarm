# /worktree-list

Lists all worktrees, optionally filtered by project.

## Usage

`/worktree-list [PROJECT]`

Examples:
- `/worktree-list` - List all worktrees across all projects
- `/worktree-list myapp` - List only myapp worktrees

## Instructions

1. Parse the optional PROJECT from `$ARGUMENTS`
   - If empty, list all projects
   - If provided, filter to that project only

2. Run the list command:
   ```bash
   branch-env list ${PROJECT}
   ```

3. Display the output:
   - Show table with columns: Project, Slug, Port, Status, Tmux
   - If no worktrees found, indicate that clearly
