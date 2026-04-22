require "open3"
require "fileutils"

class WorktreeService
  class Error < StandardError; end

  BRANCH_PREFIX = "tentacle/".freeze

  class << self
    def ensure(tentacle_id:, repo_root: Rails.root, worktree_root: nil, link_shared: true)
      repo_root = Pathname.new(repo_root)
      path = Pathname.new(path_for(tentacle_id: tentacle_id, repo_root: repo_root, worktree_root: worktree_root))
      branch = branch_for(tentacle_id)

      return path.to_s if registered?(path.to_s, repo_root: repo_root)

      FileUtils.mkdir_p(path.parent)
      FileUtils.remove_entry(path.to_s) if File.directory?(path)

      args = ["worktree", "add"]
      args.concat(branch_exists?(branch, repo_root: repo_root) ? [path.to_s, branch] : ["-b", branch, path.to_s])
      run_git!(args, repo_root: repo_root)
      link_shared_paths(path: path, repo_root: repo_root) if link_shared
      path.to_s
    end

    def remove(tentacle_id:, repo_root: Rails.root, worktree_root: nil)
      repo_root = Pathname.new(repo_root)
      path = path_for(tentacle_id: tentacle_id, repo_root: repo_root, worktree_root: worktree_root)
      branch = branch_for(tentacle_id)

      if registered?(path, repo_root: repo_root)
        run_git(["worktree", "remove", "--force", path], repo_root: repo_root)
      end
      FileUtils.remove_entry(path) if File.directory?(path)
      run_git(["branch", "-D", branch], repo_root: repo_root) if branch_exists?(branch, repo_root: repo_root)
      nil
    end

    def path_for(tentacle_id:, repo_root: Rails.root, worktree_root: nil)
      base = worktree_root ? Pathname.new(worktree_root) : Pathname.new(repo_root).join("tmp/tentacles")
      base.join(tentacle_id.to_s).to_s
    end

    private

    # Tentacle worktrees are bare checkouts of the working tree — they lack
    # any gitignored runtime files the main repo depends on. Without these,
    # a Ruby process spawned from the worktree (bin/mcp-server, bundle exec
    # rspec, Rails.application.initialize!) fails on Bundler::GemNotFound or
    # `Missing secret_key_base`. Symlink each path instead of copying so the
    # worktree always reflects the main repo.
    SHARED_PATHS = [
      "vendor/bundle",
      ".bundle",
      "config/master.key"
    ].freeze

    def link_shared_paths(path:, repo_root:)
      SHARED_PATHS.each do |rel|
        source = repo_root.join(rel)
        target = path.join(rel)
        next unless source.exist?
        next if target.symlink? || target.exist?
        FileUtils.mkdir_p(target.parent)
        FileUtils.ln_s(source.to_s, target.to_s)
      end
    end

    def branch_for(tentacle_id)
      "#{BRANCH_PREFIX}#{tentacle_id}"
    end

    def registered?(path, repo_root:)
      out, status = run_git(["worktree", "list", "--porcelain"], repo_root: repo_root)
      return false unless status.success?
      out.each_line.any? { |line| line.chomp == "worktree #{path}" }
    end

    def branch_exists?(branch, repo_root:)
      _out, status = run_git(["show-ref", "--verify", "--quiet", "refs/heads/#{branch}"], repo_root: repo_root)
      status.success?
    end

    def run_git!(args, repo_root:)
      out, status = run_git(args, repo_root: repo_root)
      raise Error, "git #{args.join(' ')} failed: #{out}" unless status.success?
      [out, status]
    end

    def run_git(args, repo_root:)
      Open3.capture2e("git", *args, chdir: repo_root.to_s)
    end
  end
end
