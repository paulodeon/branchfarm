# frozen_string_literal: true

module BranchEnv
  class Caddy
    TEMPLATE = <<~ERB
      @<%= snippet_name %> host <%= app_host %> *.<%= app_host %>
      handle @<%= snippet_name %> {
        reverse_proxy 127.0.0.1:<%= port %>
      }
    ERB

    def initialize(snippets_dir:, runner:)
      @snippets_dir = snippets_dir
      @runner = runner
      FileUtils.mkdir_p(@snippets_dir) unless @runner.dry_run?
    end

    def write_snippet(project:, slug:, app_host:, port:)
      snippet_name = "#{project}_#{slug.tr('-', '_')}"
      snippet_path = File.join(@snippets_dir, "#{project}-#{slug}.caddy")

      content = ERB.new(TEMPLATE).result_with_hash(
        snippet_name: snippet_name,
        app_host: app_host,
        port: port
      )

      puts "Writing Caddy snippet: #{snippet_path}"
      if @runner.dry_run?
        puts "  [dry-run] Would write:\n#{content.gsub(/^/, '    ')}"
      else
        File.write(snippet_path, content)
      end

      snippet_path
    end

    def remove_snippet(project:, slug:)
      snippet_path = File.join(@snippets_dir, "#{project}-#{slug}.caddy")
      if File.exist?(snippet_path)
        puts "Removing Caddy snippet: #{snippet_path}"
        File.delete(snippet_path) unless @runner.dry_run?
      end
    end

    def reload
      caddyfile = find_caddyfile
      puts "Reloading Caddy..."
      @runner.run("caddy", "reload", "--config", caddyfile)
    end

    private

    def find_caddyfile
      # Try common locations
      candidates = [
        `brew --prefix 2>/dev/null`.strip + "/etc/caddy/Caddyfile",
        "/etc/caddy/Caddyfile",
        "/usr/local/etc/caddy/Caddyfile"
      ]

      candidates.find { |path| File.exist?(path) } ||
        raise(Error, "Could not find Caddyfile. Tried: #{candidates.join(', ')}")
    end
  end
end
