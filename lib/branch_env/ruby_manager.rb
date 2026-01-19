# frozen_string_literal: true

module BranchEnv
  class RubyManager
    SUPPORTED = %w[rbenv asdf mise system].freeze

    def initialize(manager_name)
      @manager = manager_name.to_s
      unless SUPPORTED.include?(@manager)
        raise Error, "Unsupported ruby_manager '#{@manager}'. Choose from: #{SUPPORTED.join(', ')}"
      end
    end

    # Install a Ruby version if it is not already present.
    def install_ruby(version, runner:)
      case @manager
      when "rbenv"
        runner.run("rbenv", "install", "-s", version)
      when "asdf"
        runner.run("asdf", "install", "ruby", version)
      when "mise"
        runner.run("mise", "install", "ruby@#{version}")
      when "system"
        # nothing to do
      end
    end

    # Pin the Ruby version for a worktree directory.
    def set_local_version(version, chdir:, runner:)
      case @manager
      when "rbenv"
        runner.run("rbenv", "local", version, chdir: chdir)
      when "asdf"
        runner.run("asdf", "local", "ruby", version, chdir: chdir)
      when "mise"
        runner.run("mise", "use", "--path", chdir, "ruby@#{version}")
      when "system"
        # nothing to do
      end
    end

    # Return command prefix array for running commands under the managed Ruby.
    # e.g. ["rbenv", "exec", "ruby"] or just ["ruby"] for system.
    def exec_prefix
      case @manager
      when "rbenv"  then %w[rbenv exec ruby]
      when "asdf"   then %w[asdf exec ruby]
      when "mise"   then %w[mise exec -- ruby]
      when "system" then %w[ruby]
      end
    end

    # Return command prefix for running bundle commands under the managed Ruby.
    def bundle_exec_prefix
      case @manager
      when "rbenv"  then %w[rbenv exec bundle]
      when "asdf"   then %w[asdf exec bundle]
      when "mise"   then %w[mise exec -- bundle]
      when "system" then %w[bundle]
      end
    end

    # Return env vars that pin the Ruby version for subprocesses.
    def version_env(ruby_version)
      case @manager
      when "rbenv"  then { "RBENV_VERSION" => ruby_version }
      when "asdf"   then { "ASDF_RUBY_VERSION" => ruby_version }
      when "mise"   then { "MISE_RUBY_VERSION" => ruby_version }
      when "system" then {}
      end
    end

    # Parse the Ruby version from the appropriate file in a worktree.
    def parse_version(worktree_path, version_file)
      path = File.join(worktree_path, version_file)
      raise Error, "Missing #{version_file} in worktree" unless File.exist?(path)

      content = File.read(path).strip

      case version_file
      when ".tool-versions"
        # Format: ruby 3.3.4
        match = content.lines.find { |l| l.strip.start_with?("ruby ") }
        raise Error, "No ruby entry in #{version_file}" unless match
        match.strip.split(/\s+/, 2).last
      when /\.mise\.toml/
        # Format: ruby = "3.3.4"
        match = content.lines.find { |l| l.strip =~ /\Aruby\s*=/ }
        raise Error, "No ruby entry in #{version_file}" unless match
        match.strip.split("=", 2).last.gsub(/["'\s]/, "")
      else
        # .ruby-version — just the version string
        content
      end
    end
  end
end
