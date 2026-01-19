# frozen_string_literal: true

require "json"

module BranchEnv
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    class_option :dry_run, type: :boolean, default: false, desc: "Show what would be done without making changes"

    desc "create PROJECT/BRANCH", "Set up environment for a branch"
    long_desc <<~DESC
      Creates a development environment for the specified branch:
      - Creates a git worktree
      - Allocates a port
      - Writes .env/.envrc files
      - Sets up Caddy reverse proxy
      - Creates databases
      - Installs dependencies

      You can specify project and branch as "PROJECT/BRANCH" or "PROJECT BRANCH".
    DESC
    option :port, type: :numeric, desc: "Override port (default: auto-allocate)"
    option :slug, type: :string, desc: "Override slug (default: slugified branch name)"
    option :no_deps, type: :boolean, default: false, desc: "Skip dependency installation"
    option :no_db, type: :boolean, default: false, desc: "Skip database creation"
    option :no_caddy, type: :boolean, default: false, desc: "Skip Caddy configuration"
    option :no_tmux, type: :boolean, default: false, desc: "Skip tmux session creation"
    def create(project_branch, branch = nil)
      project, branch = parse_project_branch(project_branch, branch)
      config = Config.new(project)
      runner = Runner.new(dry_run: options[:dry_run])
      slug = options[:slug] || slugify(branch)

      puts "=" * 60
      puts "Creating environment"
      puts "=" * 60
      puts "  Project:  #{config.project_key}"
      puts "  Branch:   #{branch}"
      puts "  Slug:     #{slug}"
      puts "  Dry run:  #{options[:dry_run]}"
      puts "=" * 60
      puts

      # 1. Allocate port
      port_registry = PortRegistry.new(dry_run: options[:dry_run])
      port_key = "#{config.project_key}:#{slug}"
      port = if options[:port]
               port_registry.register(port_key, options[:port])
             else
               port_registry.allocate(port_key, config.port_range)
             end

      # Derive names
      app_host = config.base_domain_template % slug
      db_prefix = config.db_prefix_template % slug
      dev_db = "#{db_prefix}_dev"
      test_db = "#{db_prefix}_test"

      puts "  Host:     #{app_host}"
      puts "  Port:     #{port}"
      puts "  Dev DB:   #{dev_db}"
      puts "  Test DB:  #{test_db}"
      puts

      # Start independent work (Caddy + DB) in background threads
      quiet_runner = Runner.new(dry_run: options[:dry_run], printer: :quiet)
      background_errors = []

      caddy_thread = unless skip_caddy?
        Thread.new do
          caddy = Caddy.new(snippets_dir: config.caddy_snippets_dir, runner: quiet_runner)
          caddy.write_snippet(project: config.project_key, slug: slug, app_host: app_host, port: port)
          caddy.reload
        rescue => e
          background_errors << "Caddy: #{e.message}"
        end
      end

      db_create_thread = unless options[:no_db]
        Thread.new do
          db = Database.new(runner: quiet_runner)
          db.create_if_missing(dev_db)
          db.create_if_missing(test_db)
        rescue => e
          background_errors << "Database: #{e.message}"
        end
      end

      # 2. Create/update worktree
      step("Setting up worktree") do
        git = Git.new(repo_dir: config.repo_dir, worktrees_dir: config.worktrees_dir, runner: runner)
        git.setup_worktree(branch, slug)
      end

      worktree_path = File.join(config.worktrees_dir, slug)

      # 3. Write environment files
      env_file = nil
      step("Writing environment files") do
        env = Environment.new(runner: runner)

        if config.use_env_file?
          env_file = env.write_env_file(worktree_path,
            app_host: app_host, port: port, dev_db: dev_db, test_db: test_db,
            base_env_file: config.base_env_file)
        else
          puts "  Skipping .env (use_env_file: false)"
        end

        if config.use_envrc?
          env.write_envrc_file(worktree_path,
            app_host: app_host, port: port, dev_db: dev_db, test_db: test_db,
            base_env_file: config.base_env_file)
          env.allow_direnv(worktree_path)
        else
          puts "  Skipping .envrc (use_envrc: false)"
        end
      end

      # 3b. Copy extra files
      if config.copy_files_dir
        step("Copying project files") do
          env = Environment.new(runner: runner)
          env.copy_files(worktree_path, copy_files_dir: config.copy_files_dir)
        end
      end

      # 3c. Create symlinks
      if config.symlinks
        step("Creating symlinks") do
          env = Environment.new(runner: runner)
          env.create_symlinks(worktree_path, symlinks: config.symlinks)
        end
      end

      # Wait for background threads (Caddy + DB creation)
      [caddy_thread, db_create_thread].compact.each(&:join)
      if background_errors.any?
        raise Error, "Background tasks failed: #{background_errors.join('; ')}"
      end
      puts
      puts "  Caddy: configured" unless skip_caddy?
      puts "  Databases: created" unless options[:no_db]

      # 6. Install dependencies
      unless options[:no_deps]
        step("Installing Ruby") do
          install_ruby(worktree_path, config, runner)
        end

        step("Installing gems") do
          install_gems(worktree_path, config, runner)
        end

        if config.js_install_cmd && !config.js_install_cmd.empty?
          step("Installing JS dependencies") do
            install_js_deps(worktree_path, config, runner, env_file)
          end
        end

        if config.js_build_cmd && !config.js_build_cmd.empty?
          step("Building JS assets") do
            build_js_assets(worktree_path, config, runner, env_file)
          end
        end
      end

      # 7. Prepare Rails databases
      unless options[:no_db]
        step("Preparing Rails database") do
          db = Database.new(runner: runner)
          db_opts = {
            env_file: env_file,
            base_env_file: config.base_env_file,
            ruby_manager: config.ruby_manager,
            ruby_version_file: config.ruby_version_file
          }

          db.prepare_rails(worktree_path, command: config.rails_db_prepare_cmd, **db_opts)
          db.prepare_rails(worktree_path, command: config.rails_db_prepare_cmd, rails_env: "test", **db_opts)

          if config.rails_db_seed_cmd && !config.rails_db_seed_cmd.strip.empty?
            db.prepare_rails(worktree_path, command: config.rails_db_seed_cmd, **db_opts)
          end

          if config.parallel_test_setup_cmd && !config.parallel_test_setup_cmd.strip.empty?
            db.prepare_rails(worktree_path, command: config.parallel_test_setup_cmd, rails_env: "test", **db_opts)
          end
        end
      end

      # 8. Run post-create commands
      if config.post_create_commands.any?
        step("Running post-create commands") do
          rm = ruby_manager(config)
          config.post_create_commands.each do |cmd|
            puts "  Running: #{cmd}"
            env = worktree_env(worktree_path, config)
            runner.run_unbundled(*rm.exec_prefix, *cmd.split,
              chdir: worktree_path, env: env)
          end
        end
      end

      # 9. Create tmux session
      tmux_session_name = tmux_session_name(config.project_key, slug)
      unless skip_tmux?
        step("Creating tmux session") do
          tmux = Tmux.new(runner: runner)
          tmux.create_session(name: tmux_session_name, directory: worktree_path)
        end
      end

      puts
      puts "=" * 60
      puts "Ready for development!"
      puts "=" * 60
      puts
      puts "  Branch:     #{branch}"
      puts "  Worktree:   #{worktree_path}"
      puts "  URL:        http://#{app_host}"
      puts "  Port:       #{port}"
      puts "  Dev DB:     #{dev_db}"
      puts "  Test DB:    #{test_db}"
      puts
      puts "Commands:"
      puts "  cd #{worktree_path}"
      puts "  direnv allow" if config.use_envrc?
      puts "  bin/dev                          # Start server"
      puts "  tmux attach -t #{tmux_session_name}" unless skip_tmux?
      puts
    end

    desc "remove PROJECT/BRANCH", "Remove a branch environment"
    option :slug, type: :string, desc: "Override slug (default: slugified branch name)"
    option :keep_db, type: :boolean, default: false, desc: "Keep databases"
    def remove(project_branch, branch = nil)
      project, branch = parse_project_branch(project_branch, branch)
      config = Config.new(project)
      runner = Runner.new(dry_run: options[:dry_run])
      slug = options[:slug] || slugify(branch)

      puts "Removing environment: #{config.project_key}/#{slug}"
      puts

      port_key = "#{config.project_key}:#{slug}"
      db_prefix = config.db_prefix_template % slug
      dev_db = "#{db_prefix}_dev"
      test_db = "#{db_prefix}_test"

      # Kill tmux session
      unless skip_tmux?
        step("Killing tmux session") do
          tmux = Tmux.new(runner: runner)
          tmux.kill_session(tmux_session_name(config.project_key, slug))
        end
      end

      # Remove Caddy snippet
      unless skip_caddy?
        step("Removing Caddy config") do
          caddy = Caddy.new(snippets_dir: config.caddy_snippets_dir, runner: runner)
          caddy.remove_snippet(project: config.project_key, slug: slug)
          caddy.reload rescue nil
        end
      end

      # Remove worktree
      step("Removing worktree") do
        git = Git.new(repo_dir: config.repo_dir, worktrees_dir: config.worktrees_dir, runner: runner)
        git.remove_worktree(slug)
      end

      # Drop databases
      unless options[:keep_db]
        step("Dropping databases") do
          db = Database.new(runner: runner)
          db.drop(dev_db)
          db.drop(test_db)
        end
      end

      # Remove port registration
      step("Removing port registration") do
        PortRegistry.new.remove(port_key)
      end

      puts
      puts "Environment removed."
    end

    desc "list [PROJECT]", "List all environments"
    def list(project = nil)
      port_registry = PortRegistry.new

      entries = if project
                  config = Config.new(project)
                  port_registry.all_for_project(config.project_key)
                else
                  port_registry.entries
                end

      if entries.empty?
        puts "No environments found."
        return
      end

      rows = entries.map do |key, port|
        proj, slug = key.split(":", 2)
        config = Config.new(proj) rescue nil
        worktree = config ? File.join(config.worktrees_dir, slug) : "?"
        exists = File.exist?(worktree)
        status = exists ? "ok" : "missing"
        tmux_name = tmux_session_name(proj, slug)
        tmux_status = Tmux.session_exists?(tmux_name) ? tmux_name : "-"
        [proj, slug, port, status, tmux_status]
      end

      table = TTY::Table.new(header: ["Project", "Slug", "Port", "Status", "Tmux"], rows: rows)
      puts table.render(:unicode, padding: [0, 1])
    end

    desc "setup PROJECT", "Set up workspace config for a project"
    long_desc <<~DESC
      Checks that .branchfarm.yml exists for the project and sets up the
      .branchfarm/ directory with base.env (from base.env.example) and files/.
    DESC
    def setup(project)
      config = Config.new(project)
      workspace = config.workspace_root
      branchfarm_dir = File.join(workspace, ".branchfarm")

      example = File.join(branchfarm_dir, "base.env.example")
      base_env = File.join(branchfarm_dir, "base.env")
      files_dir = File.join(branchfarm_dir, "files")

      puts "Setting up #{project} workspace at #{workspace}"
      puts

      unless File.exist?(File.join(workspace, ".branchfarm.yml"))
        raise Error, "No .branchfarm.yml found in #{workspace}"
      end
      puts "  .branchfarm.yml: found"

      FileUtils.mkdir_p(files_dir)
      puts "  .branchfarm/files/: ready"

      if File.exist?(base_env)
        puts "  .branchfarm/base.env: already exists"
      elsif File.exist?(example)
        FileUtils.cp(example, base_env)
        puts "  .branchfarm/base.env: created from base.env.example"
        puts
        puts "  >>> Edit #{base_env} with your secrets"
      else
        puts "  .branchfarm/base.env.example: not found (skipping)"
      end

      puts
      puts "Done. You can now run: bin/branch-env create #{project}/BRANCH"
    end

    desc "status PROJECT/BRANCH", "Check status of an environment"
    option :slug, type: :string, desc: "Override slug"
    def status(project_branch, branch = nil)
      project, branch = parse_project_branch(project_branch, branch)
      config = Config.new(project)
      slug = options[:slug] || slugify(branch)
      port_key = "#{config.project_key}:#{slug}"

      port_registry = PortRegistry.new
      port = port_registry.get(port_key)

      unless port
        puts "Environment not found: #{config.project_key}/#{slug}"
        return
      end

      worktree_path = File.join(config.worktrees_dir, slug)
      app_host = config.base_domain_template % slug
      db_prefix = config.db_prefix_template % slug
      dev_db = "#{db_prefix}_dev"
      test_db = "#{db_prefix}_test"

      db = Database.new(runner: Runner.new)

      puts "Environment: #{config.project_key}/#{slug}"
      puts
      tmux_name = tmux_session_name(config.project_key, slug)
      tmux_exists = Tmux.session_exists?(tmux_name)

      puts "  Port:       #{port} #{port_in_use?(port) ? '(in use)' : '(free)'}"
      puts "  Host:       #{app_host}"
      puts "  Worktree:   #{worktree_path} #{File.exist?(worktree_path) ? '(exists)' : '(missing)'}"
      puts "  Dev DB:     #{dev_db} #{db.database_exists?(dev_db) ? '(exists)' : '(missing)'}"
      puts "  Test DB:    #{test_db} #{db.database_exists?(test_db) ? '(exists)' : '(missing)'}"
      puts "  Tmux:       #{tmux_name} #{tmux_exists ? '(active)' : '(not running)'}"
    end

    private

    def skip_caddy?
      options[:no_caddy] || !BranchEnv.settings.caddy?
    end

    def skip_tmux?
      options[:no_tmux] || !BranchEnv.settings.tmux?
    end

    def parse_project_branch(project_branch, branch)
      if branch.nil?
        parts = project_branch.split("/", 2)
        if parts.length < 2
          raise Thor::Error, "Invalid format. Use PROJECT/BRANCH or PROJECT BRANCH"
        end
        parts
      else
        [project_branch, branch]
      end
    end

    def step(name)
      puts
      puts ">>> #{name}"
      yield
      puts "    Done."
    end

    def slugify(branch)
      branch.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/^-+|-+$/, "")
    end

    def tmux_session_name(project, slug)
      "#{project}-#{slug}"
    end

    def ruby_manager(config)
      RubyManager.new(config.ruby_manager)
    end

    def port_in_use?(port)
      system("lsof -nP -iTCP:#{port} -sTCP:LISTEN >/dev/null 2>&1")
    end

    def install_ruby(worktree_path, config, runner)
      rm = ruby_manager(config)
      version = rm.parse_version(worktree_path, config.ruby_version_file)
      puts "  Installing Ruby #{version} (if needed)"
      rm.install_ruby(version, runner: runner)
      rm.set_local_version(version, chdir: worktree_path, runner: runner)
    end

    def install_gems(worktree_path, config, runner)
      rm = ruby_manager(config)
      env = worktree_env(worktree_path, config)
      bundle_prefix = rm.bundle_exec_prefix

      if config.bundle_without && !config.bundle_without.empty?
        runner.run_unbundled(*bundle_prefix, "config", "set", "without",
          config.bundle_without, chdir: worktree_path, env: env)
      end

      check_result = runner.run_unbundled!(*bundle_prefix, "check",
        chdir: worktree_path, env: env)
      if check_result.success?
        puts "  Bundle satisfied, skipping install"
      else
        runner.run_unbundled(*bundle_prefix, "install",
          chdir: worktree_path, env: env)
      end
    end

    def worktree_env(worktree_path, config)
      env = {
        "BUNDLE_GEMFILE" => File.join(worktree_path, "Gemfile")
      }
      rm = ruby_manager(config)
      version_file = File.join(worktree_path, config.ruby_version_file)
      if File.exist?(version_file)
        ruby_version = rm.parse_version(worktree_path, config.ruby_version_file)
        env.merge!(rm.version_env(ruby_version))
      end
      env
    end

    def install_js_deps(worktree_path, config, runner, env_file)
      env_vars = load_env_for_js(env_file, config)
      cmd = config.js_install_cmd

      # If project uses packageManager field in package.json, use corepack
      if uses_corepack?(worktree_path)
        puts "  Detected packageManager field, using corepack..."
        corepack_path = find_corepack
        if corepack_path
          # Replace 'yarn' with full path to corepack + yarn
          cmd = cmd.gsub(/\byarn\b/, "#{corepack_path} yarn")
        else
          puts "  Warning: corepack not found, falling back to regular yarn"
        end
      end

      runner.run(cmd, chdir: worktree_path, env: env_vars)
    end

    def build_js_assets(worktree_path, config, runner, env_file)
      env_vars = load_env_for_js(env_file, config)
      runner.run(config.js_build_cmd, chdir: worktree_path, env: env_vars)
    end

    def load_env_for_js(env_file, config)
      vars = {}
      [config.base_env_file, env_file].compact.each do |path|
        next unless File.exist?(path)

        File.readlines(path).each do |line|
          line = line.strip
          next if line.empty? || line.start_with?("#")

          if line =~ /\A(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)\z/
            vars[$1] = parse_env_value($2)
          end
        end
      end

      if config.require_npm_token? && !vars["NPM_TOKEN"]
        raise Error, "NPM_TOKEN not set; add it to base env file"
      end

      vars
    end

    def parse_env_value(raw)
      raw = raw.strip
      return "" if raw.empty?

      # Handle quoted values
      if raw.start_with?('"')
        # Find closing quote (not escaped)
        if raw =~ /\A"((?:[^"\\]|\\.)*)"/
          return $1.gsub(/\\./) { |m| m[1] }
        end
      elsif raw.start_with?("'")
        # Single quotes: no escape processing
        if raw =~ /\A'([^']*)'/
          return $1
        end
      else
        # Unquoted: strip inline comment
        raw = raw.split(/\s+#/, 2).first || ""
      end

      raw
    end

    def uses_corepack?(worktree_path)
      package_json = File.join(worktree_path, "package.json")
      return false unless File.exist?(package_json)

      begin
        data = JSON.parse(File.read(package_json))
        data.key?("packageManager")
      rescue JSON::ParserError
        false
      end
    end

    def find_corepack
      # Check common locations for corepack
      nvm_dir = ENV["NVM_DIR"] || File.expand_path("~/.nvm")

      # Try nvm node versions (prefer newer versions)
      if Dir.exist?(nvm_dir)
        node_versions_dir = File.join(nvm_dir, "versions", "node")
        if Dir.exist?(node_versions_dir)
          versions = Dir.children(node_versions_dir).sort_by { |v| Gem::Version.new(v.sub(/^v/, "")) rescue v }.reverse
          versions.each do |version|
            corepack = File.join(node_versions_dir, version, "bin", "corepack")
            return corepack if File.executable?(corepack)
          end
        end
      end

      # Try homebrew node
      brew_prefix = `brew --prefix 2>/dev/null`.strip
      unless brew_prefix.empty?
        homebrew_corepack = File.join(brew_prefix, "opt", "node", "bin", "corepack")
        return homebrew_corepack if File.executable?(homebrew_corepack)
      end

      # Try system PATH as fallback
      system_corepack = `which corepack 2>/dev/null`.strip
      return system_corepack unless system_corepack.empty?

      nil
    end
  end
end
