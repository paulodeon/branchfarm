# frozen_string_literal: true

module BranchEnv
  class Settings
    CONFIG_PATH = File.join(ROOT, "config.yml")

    DEFAULTS = {
      "caddy" => true,
      "tmux" => true,
      "caddy_snippets_dir" => File.join(
        (`brew --prefix 2>/dev/null`.strip.then { |p| p.empty? ? "/usr/local" : p }),
        "var", "branchfarm", "caddy", "snippets"
      ),
      "workspaces_dir" => File.join(ENV["HOME"], "Code"),
      "ruby_manager" => "rbenv"
    }.freeze

    def initialize
      @data = DEFAULTS.merge(load_config)
    end

    def caddy?
      @data["caddy"]
    end

    def tmux?
      @data["tmux"]
    end

    def caddy_snippets_dir
      @data["caddy_snippets_dir"]
    end

    def workspaces_dir
      @data["workspaces_dir"]
    end

    def ruby_manager
      @data["ruby_manager"]
    end

    def [](key)
      @data[key.to_s]
    end

    private

    def load_config
      return {} unless File.exist?(CONFIG_PATH)

      YAML.safe_load(File.read(CONFIG_PATH), permitted_classes: [], aliases: true) || {}
    end
  end
end
