# frozen_string_literal: true

module BranchEnv
  class Git
    def initialize(repo_dir:, worktrees_dir:, runner:)
      @repo_dir = repo_dir
      @worktrees_dir = worktrees_dir
      @runner = runner
    end

    def setup_worktree(branch, slug)
      worktree_path = File.join(@worktrees_dir, slug)
      FileUtils.mkdir_p(@worktrees_dir) unless @runner.dry_run?

      if worktree_exists?(worktree_path)
        update_worktree(worktree_path, branch)
      else
        create_worktree(worktree_path, branch)
      end

      worktree_path
    end

    def remove_worktree(slug)
      worktree_path = File.join(@worktrees_dir, slug)
      return unless worktree_exists?(worktree_path)

      @runner.run("git", "-C", @repo_dir, "worktree", "remove", "--force", worktree_path)
    end

    def list_worktrees
      result = @runner.run!("git", "-C", @repo_dir, "worktree", "list", "--porcelain")
      parse_worktree_list(result.out)
    end

    private

    def worktree_exists?(path)
      File.exist?(File.join(path, ".git")) || File.directory?(File.join(path, ".git"))
    end

    def update_worktree(path, branch)
      puts "Worktree exists at #{path}, updating..."
      @runner.run("git", "-C", path, "fetch", "-p")
      @runner.run!("git", "-C", path, "checkout", branch) rescue nil
      @runner.run!("git", "-C", path, "checkout", "-b", branch, "origin/#{branch}") rescue nil
      @runner.run!("git", "-C", path, "pull", "--ff-only") rescue nil
    end

    def create_worktree(path, branch)
      puts "Creating worktree at #{path}..."
      @runner.run("git", "-C", @repo_dir, "fetch", "-p")

      # Try remote branch first, then local, then create new
      if remote_branch_exists?(branch)
        @runner.run("git", "-C", @repo_dir, "worktree", "add", path, "-B", branch, "origin/#{branch}")
      elsif local_branch_exists?(branch)
        @runner.run("git", "-C", @repo_dir, "worktree", "add", path, branch)
      else
        @runner.run("git", "-C", @repo_dir, "worktree", "add", path, "-b", branch)
      end
    end

    def remote_branch_exists?(branch)
      result = @runner.run!("git", "-C", @repo_dir, "show-ref", "--verify", "--quiet", "refs/remotes/origin/#{branch}")
      result.success?
    rescue
      false
    end

    def local_branch_exists?(branch)
      result = @runner.run!("git", "-C", @repo_dir, "show-ref", "--verify", "--quiet", "refs/heads/#{branch}")
      result.success?
    rescue
      false
    end

    def parse_worktree_list(output)
      worktrees = []
      current = {}

      output.each_line do |line|
        line = line.strip
        if line.empty?
          worktrees << current unless current.empty?
          current = {}
        elsif line.start_with?("worktree ")
          current[:path] = line.sub("worktree ", "")
        elsif line.start_with?("HEAD ")
          current[:head] = line.sub("HEAD ", "")
        elsif line.start_with?("branch ")
          current[:branch] = line.sub("branch refs/heads/", "")
        elsif line == "bare"
          current[:bare] = true
        end
      end
      worktrees << current unless current.empty?
      worktrees
    end
  end
end
