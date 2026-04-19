require "open3"
require "fileutils"

class WorktreeService
  class Error < StandardError; end

  BRANCH_PREFIX = "tentacle/".freeze

  class << self
    def ensure(tentacle_id:, repo_root: Rails.root)
      repo_root = Pathname.new(repo_root)
      path = Pathname.new(path_for(tentacle_id: tentacle_id, repo_root: repo_root))
      branch = branch_for(tentacle_id)

      return path.to_s if registered?(path.to_s, repo_root: repo_root)

      FileUtils.mkdir_p(path.parent)
      FileUtils.remove_entry(path.to_s) if File.directory?(path)

      args = ["worktree", "add"]
      args.concat(branch_exists?(branch, repo_root: repo_root) ? [path.to_s, branch] : ["-b", branch, path.to_s])
      run_git!(args, repo_root: repo_root)
      path.to_s
    end

    def remove(tentacle_id:, repo_root: Rails.root)
      repo_root = Pathname.new(repo_root)
      path = path_for(tentacle_id: tentacle_id, repo_root: repo_root)
      branch = branch_for(tentacle_id)

      if registered?(path, repo_root: repo_root)
        run_git(["worktree", "remove", "--force", path], repo_root: repo_root)
      end
      FileUtils.remove_entry(path) if File.directory?(path)
      run_git(["branch", "-D", branch], repo_root: repo_root) if branch_exists?(branch, repo_root: repo_root)
      nil
    end

    def path_for(tentacle_id:, repo_root: Rails.root)
      Pathname.new(repo_root).join("tmp/tentacles", tentacle_id.to_s).to_s
    end

    private

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
