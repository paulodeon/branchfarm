# frozen_string_literal: true

require "bundler"

module BranchEnv
  class Runner
    def initialize(dry_run: false, printer: :pretty)
      @dry_run = dry_run
      @cmd = TTY::Command.new(printer: printer)
    end

    def run(*args, **opts)
      if @dry_run
        puts "  [dry-run] #{args.join(' ')}"
        TTY::Command::Result.new(0, "", "")
      else
        @cmd.run(*args, **opts)
      end
    end

    def run!(*args, **opts)
      if @dry_run
        puts "  [dry-run] #{args.join(' ')}"
        TTY::Command::Result.new(0, "", "")
      else
        @cmd.run!(*args, **opts)
      end
    end

    # Run a command in an unbundled environment (clears bundler pollution)
    def run_unbundled(*args, **opts)
      if @dry_run
        puts "  [dry-run] #{args.join(' ')}"
        TTY::Command::Result.new(0, "", "")
      else
        Bundler.with_unbundled_env do
          @cmd.run(*args, **opts)
        end
      end
    end

    # Non-raising variant of run_unbundled (returns result, does not raise on failure)
    def run_unbundled!(*args, **opts)
      if @dry_run
        puts "  [dry-run] #{args.join(' ')}"
        TTY::Command::Result.new(0, "", "")
      else
        Bundler.with_unbundled_env do
          @cmd.run!(*args, **opts)
        end
      end
    end

    def dry_run?
      @dry_run
    end
  end
end
