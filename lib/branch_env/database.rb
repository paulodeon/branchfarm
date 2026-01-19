# frozen_string_literal: true

module BranchEnv
  class Database
    def initialize(runner:)
      @runner = runner
    end

    def create_if_missing(db_name)
      if database_exists?(db_name)
        puts "Database exists: #{db_name}"
      else
        puts "Creating database: #{db_name}"
        @runner.run("createdb", db_name)
      end
    end

    def drop(db_name)
      if database_exists?(db_name)
        puts "Dropping database: #{db_name}"
        @runner.run("dropdb", db_name)
      else
        puts "Database doesn't exist: #{db_name}"
      end
    end

    def database_exists?(db_name)
      return false if @runner.dry_run?

      result = @runner.run!("psql", "-lqt")
      databases = result.out.lines.map { |l| l.split("|").first&.strip }.compact
      databases.include?(db_name)
    end

    def prepare_rails(worktree_path, env_file:, base_env_file:, command:, ruby_manager:, ruby_version_file: ".ruby-version", rails_env: nil)
      if command.nil? || command.strip.empty?
        puts "Skipping: no command specified"
        return
      end

      env_vars = load_env_vars(env_file, base_env_file)
      env_vars["RAILS_ENV"] = rails_env if rails_env
      env_vars["BUNDLE_GEMFILE"] = File.join(worktree_path, "Gemfile")

      # Set manager-specific env var to pin the Ruby version
      rm = RubyManager.new(ruby_manager)
      begin
        version = rm.parse_version(worktree_path, ruby_version_file)
        env_vars.merge!(rm.version_env(version))
      rescue Error
        # version file may not exist yet; proceed without pinning
      end

      puts "Running: #{command} #{"(RAILS_ENV=#{rails_env})" if rails_env}"
      cmd_parts = command.split
      @runner.run_unbundled(*rm.exec_prefix, *cmd_parts, chdir: worktree_path, env: env_vars)
    end

    private

    def load_env_vars(env_file, base_env_file)
      vars = {}
      [base_env_file, env_file].each do |path|
        next unless path && File.exist?(path)

        File.readlines(path).each do |line|
          line = line.strip
          next if line.empty? || line.start_with?("#")

          if line =~ /\A([A-Za-z_][A-Za-z0-9_]*)=(.*)\z/
            key, value = $1, $2
            # Remove surrounding quotes if present
            value = value.gsub(/\A["']|["']\z/, "")
            vars[key] = value
          end
        end
      end
      vars
    end
  end
end
