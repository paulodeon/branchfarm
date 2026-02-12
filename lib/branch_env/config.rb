# frozen_string_literal: true

module BranchEnv
  class Config
    REQUIRED_KEYS = %w[
      project_key
      repo_dir
      worktrees_dir
      base_env_file
      base_domain_template
      port_range_start
      port_range_end
      db_prefix_template
    ].freeze

    attr_reader :data, :project_key, :workspace_root

    def initialize(project_name)
      @project_name = project_name
      @config_path = find_config_path(project_name)
      @workspace_root = File.dirname(@config_path)

      @data = load_config
      @project_key = @data["project_key"]
      validate!
    end

    def [](key)
      @data[key.to_s]
    end

    def repo_dir
      expand_path(@data["repo_dir"])
    end

    def worktrees_dir
      expand_path(@data["worktrees_dir"])
    end

    def caddy_snippets_dir
      expand_path(@data["caddy_snippets_dir"] || BranchEnv.settings.caddy_snippets_dir)
    end

    def base_env_file
      expand_path(@data["base_env_file"])
    end

    def base_domain_template
      @data["base_domain_template"]
    end

    def port_range
      @data["port_range_start"]..@data["port_range_end"]
    end

    def db_prefix_template
      @data["db_prefix_template"]
    end

    def use_env_file?
      @data.fetch("use_env_file", true)
    end

    def use_envrc?
      @data.fetch("use_envrc", true)
    end

    def require_npm_token?
      @data.fetch("require_npm_token", false)
    end

    def ruby_version_file
      @data.fetch("ruby_version_file", ".ruby-version")
    end

    def ruby_manager
      @data.fetch("ruby_manager", BranchEnv.settings.ruby_manager)
    end

    def bundle_without
      @data["bundle_without"]
    end

    def js_install_cmd
      @data["js_install_cmd"]
    end

    def js_build_cmd
      @data["js_build_cmd"]
    end

    def rails_db_prepare_cmd
      @data.fetch("rails_db_prepare_cmd", "bin/rails db:prepare")
    end

    def rails_db_seed_cmd
      @data["rails_db_seed_cmd"]
    end

    def parallel_test_setup_cmd
      @data["parallel_test_setup_cmd"]
    end

    def post_create_commands
      @data.fetch("post_create_commands", [])
    end

    def copy_files_dir
      dir = @data["copy_files_dir"]
      dir ? expand_path(dir) : nil
    end

    def symlinks
      links = @data["symlinks"]
      return nil unless links

      links.map do |link|
        { "source" => expand_path(link["source"]), "dest" => link["dest"] }
      end
    end

    private

    def load_config
      base = YAML.safe_load(File.read(@config_path), permitted_classes: [], aliases: true)
      local_path = @config_path.sub(/\.yml$/, ".local.yml")
      if File.exist?(local_path)
        local = YAML.safe_load(File.read(local_path), permitted_classes: [], aliases: true)
        base.merge(local)
      else
        base
      end
    end

    def find_config_path(project_name)
      # 1. Try workspace convention: <workspaces_dir>/<project>/.branchfarm.yml
      workspaces_dir = BranchEnv.settings.workspaces_dir
      workspace_config = File.join(workspaces_dir, project_name, ".branchfarm.yml")
      return workspace_config if File.exist?(workspace_config)

      # 2. Fall back to branchfarm/config/projects/<project>.yml
      legacy = File.join(BranchEnv::ROOT, "config", "projects", "#{project_name}.yml")
      return legacy if File.exist?(legacy)

      raise Error, "Unknown project '#{project_name}' (no .branchfarm.yml in #{workspaces_dir}/#{project_name}/ or #{legacy})"
    end

    def validate_repo_dir_is_not_workspace!
      # Ensure repo_dir is a standalone clone, not a worktree of the workspace repo.
      # This catches the case where master/ was accidentally created via
      # `git worktree add` from the workspace root instead of `git clone`.
      git_common_dir = `git -C #{repo_dir} rev-parse --git-common-dir 2>/dev/null`.strip
      return if git_common_dir.empty?

      workspace_git_dir = File.join(@workspace_root, ".git")
      return unless File.exist?(workspace_git_dir)

      repo_common = File.realpath(git_common_dir)
      ws_git = File.realpath(workspace_git_dir)
      if repo_common == ws_git
        raise Error, "repo_dir (#{repo_dir}) is a worktree of the workspace repo, not a standalone clone. " \
                     "Remove it and clone the correct repo: git clone <app-repo-url> #{repo_dir}"
      end
    end

    def expand_path(path)
      return nil unless path

      path
        .gsub("$WORKSPACE_ROOT", @workspace_root)
        .gsub("${WORKSPACE_ROOT}", @workspace_root)
        .gsub("$HOME", ENV["HOME"])
        .gsub("${HOME}", ENV["HOME"])
        .gsub("$BRANCHFARM_ROOT", BranchEnv::ROOT)
        .gsub("${BRANCHFARM_ROOT}", BranchEnv::ROOT)
    end

    def validate!
      missing = REQUIRED_KEYS.select { |key| @data[key].nil? || @data[key].to_s.empty? }
      if missing.any?
        raise Error, "Missing required config keys in #{@config_path}: #{missing.join(', ')}"
      end

      unless File.directory?(repo_dir)
        raise Error, "repo_dir is not a directory: #{repo_dir}"
      end

      validate_repo_dir_is_not_workspace!

      unless File.exist?(base_env_file)
        raise Error, "base_env_file not found: #{base_env_file}"
      end
    end
  end
end
