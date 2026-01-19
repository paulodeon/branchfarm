# Branchfarm

Git worktree manager for Rails projects. Creates isolated development environments per branch — each with its own port, database, Caddy route, and tmux session.

## Prerequisites

- Ruby >= 3.0
- Ruby version manager: [rbenv](https://github.com/rbenv/rbenv), [asdf](https://asdf-vm.com/), [mise](https://mise.jdx.dev/), or system Ruby
- PostgreSQL
- [Caddy](https://caddyserver.com/) — optional, see [Configuration](#configuration)
- tmux — optional, see [Configuration](#configuration)
- [direnv](https://direnv.net/) — optional, if using `.envrc` mode (see `use_envrc` below)

## Install

```bash
git clone <repo-url> ~/Code/branchfarm
cd ~/Code/branchfarm
bundle install
```

Add to your PATH (in `~/.zshrc` or equivalent):

```bash
export PATH="$HOME/Code/branchfarm/bin:$PATH"
```

### Caddy setup (optional)

Create the caddy snippets directory:

```bash
mkdir -p "$(brew --prefix)/var/branchfarm/caddy/snippets"
```

Add this import to your Caddyfile (`$(brew --prefix)/etc/caddy/Caddyfile`):

```
:80 {
    import /path/to/branchfarm/caddy/snippets/*.caddy
    respond "No caddy route registered for {host}" 404
}
```

## Configuration

Branchfarm reads local settings from `config.yml` in the branchfarm directory. Copy `config.yml.example` to get started. This file is optional — sensible defaults are used if it's missing.

```yaml
# Reverse proxy (set false if Caddy is not installed)
caddy: true

# Tmux sessions (set false to skip tmux session creation)
tmux: true

# Ruby version manager: rbenv, asdf, mise, or system
ruby_manager: rbenv

# Where to look for project workspaces
workspaces_dir: /Users/you/Code

# Where to write Caddy snippets (auto-detected from brew --prefix)
# caddy_snippets_dir: /usr/local/var/branchfarm/caddy/snippets
```

| Setting | Default | Description |
|---------|---------|-------------|
| `caddy` | `true` | Enable Caddy reverse proxy snippets. Set `false` to skip all Caddy operations. |
| `tmux` | `true` | Create tmux sessions for worktrees. Set `false` to skip. |
| `ruby_manager` | `rbenv` | Ruby version manager. Supports `rbenv`, `asdf`, `mise`, or `system`. |
| `workspaces_dir` | `$HOME/Code` | Parent directory where project workspaces live. Used to find `.branchfarm.yml` files. |
| `caddy_snippets_dir` | `$(brew --prefix)/var/branchfarm/caddy/snippets` | Directory for generated Caddy snippet files. |

CLI flags (`--no-caddy`, `--no-tmux`) override these settings per invocation.

If you set `caddy: false`, you can skip the Caddy install steps entirely (no snippets directory, no Caddyfile changes needed).

## Adding a project

Each project workspace (e.g. `~/Code/myapp`) needs a `.branchfarm.yml` at its root.

**1. Create the config file** — `~/Code/myapp/.branchfarm.yml`:

```yaml
project_key: myapp
git_host: github                # or gitlab

repo_dir: $WORKSPACE_ROOT/main  # main branch worktree
worktrees_dir: $WORKSPACE_ROOT
base_env_file: $WORKSPACE_ROOT/.branchfarm/base.env
copy_files_dir: $WORKSPACE_ROOT/.branchfarm/files

use_env_file: true              # write .env into worktrees (for dotenv/Rails)
use_envrc: false                # write .envrc into worktrees (for direnv)

base_domain_template: "myapp-%s.studio"
port_range_start: 5010
port_range_end: 5099
db_prefix_template: "myapp_%s"

# Ruby version manager override (optional, falls back to config.yml setting)
# ruby_manager: rbenv
ruby_version_file: .ruby-version
bundle_without: ""
js_install_cmd: ""
js_build_cmd: ""
require_npm_token: false

rails_db_prepare_cmd: bin/rails db:prepare
# rails_db_seed_cmd: bin/rails db:seed
# parallel_test_setup_cmd: bin/rails parallel:prepare

# post_create_commands:
#   - bin/rails tailwindcss:build

# symlinks:
#   - source: $WORKSPACE_ROOT/.claude/commands-worktree
#     dest: .claude/commands
```

**2. Create the env template** — `~/Code/myapp/.branchfarm/base.env.example`:

```
SECRET_KEY_BASE=change_me
# Add project-specific env vars here
```

**3. Run setup:**

```bash
branch-env setup myapp
# -> copies base.env.example to base.env, creates files/ dir
# -> edit .branchfarm/base.env with your actual secrets
```

**4. Gitignore** the secrets (in your workspace `.gitignore`):

```
.branchfarm/base.env
.branchfarm/files/
```

### Config variables

Paths in `.branchfarm.yml` support these variables:

| Variable | Resolves to |
|----------|-------------|
| `$WORKSPACE_ROOT` | Directory containing `.branchfarm.yml` |
| `$HOME` | Home directory |
| `$BRANCHFARM_ROOT` | Branchfarm install directory |

### Copy files

Files placed in `.branchfarm/files/` are copied into every new worktree, preserving directory structure. Useful for `.mcp.json`, IDE configs, etc.

### Config discovery

`branch-env` finds project config by convention:

1. `<workspaces_dir>/<project>/.branchfarm.yml` (default: `$HOME/Code/<project>/`)
2. `branchfarm/config/projects/<project>.yml` (legacy fallback)

The `workspaces_dir` is configurable in `config.yml`.

## Usage

```bash
# Create a worktree environment
branch-env create myapp/feature-branch

# List all environments
branch-env list
branch-env list myapp

# Check status of an environment
branch-env status myapp/feature-branch

# Remove an environment
branch-env remove myapp/feature-branch

# Set up a new project workspace
branch-env setup myapp
```

### What `create` does

1. Allocates a port from the project's range
2. Creates a git worktree
3. Writes `.env` (dotenv) and/or `.envrc` (direnv) with branch-specific variables
4. Copies files from `.branchfarm/files/`
5. Creates configured symlinks
6. Writes a Caddy snippet and reloads Caddy
7. Creates PostgreSQL databases (`<prefix>_dev`, `<prefix>_test`)
8. Installs Ruby + gems (+ JS deps if configured)
9. Runs `rails db:prepare`, seed, and parallel test setup
10. Runs post-create commands
11. Creates a tmux session

### What `remove` does

1. Kills the tmux session
2. Removes the Caddy snippet and reloads
3. Removes the git worktree
4. Drops databases
5. Frees the port

### Options

```
--dry-run     Show what would be done without making changes
--no-deps     Skip dependency installation
--no-db       Skip database creation
--no-caddy    Skip Caddy configuration
--no-tmux     Skip tmux session creation
--slug NAME   Override the auto-generated slug
--port PORT   Override port allocation
```

## Ruby version managers

Branchfarm supports multiple Ruby version managers. Set `ruby_manager` in `config.yml` (global default) or per-project in `.branchfarm.yml`:

| Manager | Install | Pin version | Exec prefix |
|---------|---------|-------------|-------------|
| `rbenv` | `rbenv install -s VERSION` | `rbenv local VERSION` | `rbenv exec` |
| `asdf` | `asdf install ruby VERSION` | `asdf local ruby VERSION` | `asdf exec` |
| `mise` | `mise install ruby@VERSION` | `mise use --path DIR ruby@VERSION` | `mise exec --` |
| `system` | (no-op) | (no-op) | (direct) |

## Directory layout

```
branchfarm/
├── bin/
│   └── branch-env          # CLI entry point
├── lib/branch_env/
│   ├── caddy.rb            # Caddy snippet management
│   ├── cli.rb              # Thor CLI commands
│   ├── config.rb           # Project config loading
│   ├── database.rb         # PostgreSQL operations
│   ├── environment.rb      # .env / .envrc writing
│   ├── git.rb              # Git worktree operations
│   ├── port_registry.rb    # Port allocation
│   ├── ruby_manager.rb     # Ruby version manager abstraction
│   ├── runner.rb           # Command execution
│   ├── settings.rb         # Local settings (config.yml)
│   └── tmux.rb             # Tmux session management
├── config.yml              # Local settings (optional, gitignored)
├── config.yml.example      # Settings template
├── state/                  # Runtime state (gitignored)
├── Gemfile
├── CLAUDE.md
└── README.md
```

Workspace layout (per project):

```
~/Code/myapp/
├── .branchfarm.yml             # Project config (tracked)
├── .branchfarm/
│   ├── base.env.example        # Env template (tracked)
│   ├── base.env                # Actual secrets (gitignored)
│   └── files/                  # Files copied to worktrees (gitignored)
├── main/                       # Main branch worktree
└── feature-branch/             # Branch worktree (created by branch-env)
```
