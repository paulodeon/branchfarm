# frozen_string_literal: true

module BranchEnv
  class Tmux
    def initialize(runner:)
      @runner = runner
    end

    def create_session(name:, directory:)
      return if session_exists?(name)

      puts "  Creating tmux session: #{name}"
      if @runner.dry_run?
        puts "  [dry-run] tmux new-session -d -s #{name} -c #{directory}"
        puts "  [dry-run] Clearing bundler environment variables from session"
      else
        system("tmux", "new-session", "-d", "-s", name, "-c", directory)
        clear_bundler_environment(name)
        replace_initial_window(name, directory)
      end
    end

    # Clears bundler/ruby environment variables from a tmux session
    # This prevents Ruby version mismatches when the worktree uses a different Ruby
    # than the one branchfarm runs under
    def clear_bundler_environment(session_name)
      bundler_vars = ENV.keys.select do |k|
        k.start_with?("BUNDLE") || k.start_with?("GEM_") || k == "RUBYLIB" ||
          k == "RBENV_VERSION" || k == "RBENV_DIR"
      end

      bundler_vars.each do |var|
        system("tmux", "set-environment", "-t", session_name, "-r", var)
      end
    end

    # Replaces the initial window (which inherited contaminated env) with a clean one
    # The set-environment -r only affects new windows, not the initial one
    def replace_initial_window(session_name, directory)
      # Create a new clean window
      system("tmux", "new-window", "-t", session_name, "-c", directory)
      # Kill the original window (index 0) which had the contaminated environment
      system("tmux", "kill-window", "-t", "#{session_name}:0")
      # Renumber windows to start from 0
      system("tmux", "move-window", "-t", session_name, "-r")
    end

    def kill_session(name)
      return unless session_exists?(name)

      puts "  Killing tmux session: #{name}"
      if @runner.dry_run?
        puts "  [dry-run] tmux kill-session -t #{name}"
      else
        system("tmux", "kill-session", "-t", name)
      end
    end

    def session_exists?(name)
      system("tmux", "has-session", "-t", name, out: File::NULL, err: File::NULL)
    end

    def self.session_exists?(name)
      system("tmux", "has-session", "-t", name, out: File::NULL, err: File::NULL)
    end
  end
end
