# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Branchfarm (`branch-env`) is a Ruby CLI tool for managing isolated development environments for Rails projects. It automates the setup of git worktrees, port allocation, environment files, Caddy reverse proxy configuration, and PostgreSQL databases for each branch.

## Commands

```bash
# Install dependencies
bundle install

# Run the CLI
bin/branch-env create PROJECT/BRANCH    # Set up environment for a branch
bin/branch-env remove PROJECT/BRANCH    # Remove a branch environment
bin/branch-env list [PROJECT]           # List all environments
bin/branch-env status PROJECT/BRANCH    # Check status of an environment
bin/branch-env setup PROJECT            # Set up workspace config for a project

# Options for create/remove
--dry-run          # Show what would be done without making changes
--port <port>      # Override port (default: auto-allocate)
--slug <slug>      # Override slug (default: slugified branch name)
--no-deps          # Skip dependency installation
--no-db            # Skip database creation
--no-caddy         # Skip Caddy configuration
--no-tmux          # Skip tmux session creation
--keep-db          # Keep databases when removing (remove only)
```

## Architecture

### Core Components (lib/branch_env/)

- **cli.rb** - Thor-based CLI with `create`, `remove`, `list`, `status`, `setup` commands
- **config.rb** - Loads project YAML config from workspace `.branchfarm.yml` or legacy `config/projects/`, validates required keys, expands path variables (`$HOME`, `$BRANCHFARM_ROOT`, `$WORKSPACE_ROOT`)
- **port_registry.rb** - Thread-safe port allocation using TSV file (`state/ports.tsv`) with file locking
- **git.rb** - Git worktree management (create/update/remove)
- **database.rb** - PostgreSQL database creation/dropping, Rails db:prepare execution
- **caddy.rb** - Generates Caddy reverse proxy snippets for branch subdomains
- **environment.rb** - Writes `.env` and `.envrc` files with per-branch variables
- **tmux.rb** - Creates/kills tmux sessions per branch (session name: `project-slug`)
- **runner.rb** - TTY::Command wrapper with dry-run support and unbundled execution
- **ruby_manager.rb** - Abstracts Ruby version management (rbenv, asdf, mise, system)
- **settings.rb** - Loads local settings from `config.yml` with sensible defaults

### Project Configuration

Projects are defined in `<workspace>/.branchfarm.yml`. Required keys:
- `project_key`, `repo_dir`, `worktrees_dir`, `base_env_file`
- `base_domain_template`, `port_range_start`, `port_range_end`, `db_prefix_template`

Templates use `%s` for slug substitution (e.g., `myapp-%s.studio` -> `myapp-my-branch.studio`).

Optional keys include `ruby_manager`, `ruby_version_file`, `js_install_cmd`, `js_build_cmd`, `copy_files_dir`, `symlinks`, `post_create_commands`, and more.

### State

- `state/ports.tsv` - Port registry (format: `project:slug\tport`)
- `state/ports.lock` - File lock for concurrent port allocation

### Config Discovery

`branch-env` finds project config by:
1. `<workspaces_dir>/<project>/.branchfarm.yml` (default: `$HOME/Code/<project>/`)
2. `branchfarm/config/projects/<project>.yml` (legacy fallback)

## Key Patterns

- The CLI uses Thor for command parsing with class_option for global `--dry-run` flag
- Runner class wraps all shell commands, respecting dry-run mode
- `run_unbundled` uses `Bundler.with_unbundled_env` to avoid polluting child processes
- Path expansion supports `$HOME`, `$BRANCHFARM_ROOT`, and `$WORKSPACE_ROOT` in YAML configs
- RubyManager abstracts version manager commands so the tool works with rbenv, asdf, mise, or no manager at all
- Caddy snippets dir and other paths auto-detect Homebrew prefix for portability
