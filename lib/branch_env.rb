# frozen_string_literal: true

require "yaml"
require "erb"
require "fileutils"
require "thor"
require "tty-command"
require "tty-table"

module BranchEnv
  ROOT = File.expand_path("..", __dir__)

  class Error < StandardError; end

  def self.settings
    @settings ||= Settings.new
  end
end

require_relative "branch_env/settings"
require_relative "branch_env/runner"
require_relative "branch_env/config"
require_relative "branch_env/ruby_manager"
require_relative "branch_env/port_registry"
require_relative "branch_env/git"
require_relative "branch_env/database"
require_relative "branch_env/caddy"
require_relative "branch_env/environment"
require_relative "branch_env/tmux"
require_relative "branch_env/cli"
