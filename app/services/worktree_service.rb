require "open3"
require "fileutils"

class WorktreeService
  class Error < StandardError; end

  # Raised by refresh_transversal_branch when the worktree carries
  # uncommitted local changes that a `git reset --hard origin/main`
  # would silently discard. Fail-closed: caller decides whether to
  # commit, stash, or wipe explicitly (via `remove` + `ensure`).
  class DirtyWorktreeError < Error; end

  BRANCH_PREFIX = "tentacle/".freeze

  class << self
    def ensure(tentacle_id:, repo_root: Rails.root, worktree_root: nil, link_shared: true)
      repo_root = Pathname.new(repo_root)
      path = Pathname.new(path_for(tentacle_id: tentacle_id, repo_root: repo_root, worktree_root: worktree_root))
      branch = branch_for(tentacle_id)

      unless registered?(path.to_s, repo_root: repo_root)
        FileUtils.mkdir_p(path.parent)
        FileUtils.remove_entry(path.to_s) if File.directory?(path)

        args = ["worktree", "add"]
        args.concat(branch_exists?(branch, repo_root: repo_root) ? [path.to_s, branch] : ["-b", branch, path.to_s])
        run_git!(args, repo_root: repo_root)
      end

      # Runtime reconciliation runs on every ensure call — new worktree
      # or already-registered. Both paths are idempotent. Covers the
      # case of a worktree registered before this fix landed that never
      # received its master.key symlink. Scope is the tentacle worktree
      # only; the backing workspace repo is intentionally left untouched
      # so `remove` can clean up everything this service created.
      link_shared_paths(path: path, repo_root: repo_root) if link_shared
      # master.key must reach the worktree regardless of link_shared:
      # dev-convenience paths (vendor/bundle, .bundle) are optional,
      # but master.key is a boot requirement for any Rails app worktree.
      ensure_rails_runtime_secrets(worktree: path, workspace: repo_root)

      # Fast-forward transversal worktrees to the current default branch
      # on every ensure call. Without this, a transversal agent
      # (Gerente/Agenda/QA/...) whose branch was created before a
      # platform change sees stale code — new MCP tools added after its
      # worktree existed do not appear. link_shared=true is the signal
      # for "transversal-on-runtime" mode; workspace-mode worktrees
      # (link_shared=false) are the agent's own work surface and get
      # managed manually.
      refresh_transversal_branch(path: path, branch: branch, repo_root: repo_root) if link_shared

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

    # Rails apps need config/master.key to decrypt credentials.yml.enc
    # at boot; without it, `require "config/environment"` blows up and
    # no child process (bin/mcp-server, bundle exec rspec) can start.
    #
    # Gated by an EXPLICIT ALLOWLIST (NEURAMD_TRUSTED_WORKSPACE_KEYS,
    # comma-separated absolute workspace paths). Relying on git origin
    # URL equality would trust any clone of the same remote, including
    # attacker-controlled forks placed in the workspace root by anyone
    # with write access there. Empty/unset env = zero linking — secure
    # default. Admin opts specific workspaces in by setting the env in
    # systemd drop-in + restarting.
    #
    # Idempotent: no-op when the target is already a healthy symlink to
    # the current Rails.root master.key, a user-owned real file, the
    # source doesn't exist, the target isn't a Rails app, or the target
    # path is not in the trusted allowlist.
    def ensure_rails_runtime_secrets(worktree:, workspace:)
      worktree = Pathname.new(worktree)
      return unless worktree.join("config/credentials.yml.enc").file?
      # Allowlist gate is keyed on the WORKSPACE (backing repo) path.
      # Worktrees inherit trust from their workspace — admin configures
      # per-workspace, not per-tentacle.
      return unless trusted_workspace_for_key?(workspace)

      key_source = Rails.root.join("config/master.key")
      return unless key_source.exist?

      key_target = worktree.join("config/master.key")
      return if healthy_symlink_to_source?(key_target, key_source)
      # A real file (not a symlink) is treated as user-owned — leave it
      # alone so local experimentation isn't clobbered.
      return if key_target.exist? && !key_target.symlink?

      # Dangling or stale symlink (pointing at a different source) gets
      # replaced. This repairs worktrees that were provisioned before
      # this fix or against an old Rails.root path.
      FileUtils.rm_f(key_target) if key_target.symlink?

      FileUtils.mkdir_p(key_target.parent)
      begin
        File.symlink(key_source.to_s, key_target.to_s)
      rescue Errno::EEXIST
        # Concurrent spawn on the same workspace beat us to it. If the
        # target now points at the right source we're done; otherwise
        # surface the race so callers see the real failure.
        raise unless healthy_symlink_to_source?(key_target, key_source)
      end
    end

    # Resets a transversal worktree's branch to match origin/<default>.
    # Idempotent — already-caught-up branches are a no-op hardreset.
    # Defensive: skips silently when the remote fetch fails (e.g.,
    # offline), when origin/<branch> doesn't exist (first boot), or
    # when the worktree is behind HEAD of its own branch in an unusual
    # way (keeps whatever the worktree has rather than risking data
    # loss). Transversal agents don't commit, so this is safe.
    DEFAULT_REMOTE_BRANCH = "main".freeze

    def refresh_transversal_branch(path:, branch:, repo_root:)
      # Fail-closed before any network/git work: refuse to discard
      # uncommitted local changes silently. The hard reset below would
      # destroy them — surface the dirty state so the caller decides.
      ensure_worktree_clean!(path: path)

      # Only fetch once per run — avoids repeated network calls when
      # multiple tentacles spawn back-to-back.
      _out, fetch_status = run_git(["fetch", "origin", DEFAULT_REMOTE_BRANCH, "--quiet"], repo_root: repo_root)
      return unless fetch_status.success?

      remote_ref = "refs/remotes/origin/#{DEFAULT_REMOTE_BRANCH}"
      _out, show_status = run_git(["show-ref", "--verify", "--quiet", remote_ref], repo_root: repo_root)
      return unless show_status.success?

      # `git -C <worktree> reset --hard origin/main` applies inside the
      # worktree and updates its own HEAD/branch. The main repo's main
      # is untouched.
      out, reset_status = Open3.capture2e("git", "reset", "--hard", "origin/#{DEFAULT_REMOTE_BRANCH}", chdir: path.to_s)
      return if reset_status.success?

      Rails.logger.warn("WorktreeService: failed to refresh #{path} on branch #{branch}: #{out}") if defined?(Rails)
    rescue DirtyWorktreeError
      raise
    rescue StandardError => e
      Rails.logger.warn("WorktreeService: refresh raised #{e.class}: #{e.message}") if defined?(Rails)
    end

    # Treats only TRACKED modifications/staged changes as "dirty" —
    # untracked files survive `git reset --hard` regardless, so they
    # do not need to gate the refresh.
    def ensure_worktree_clean!(path:)
      out, status = Open3.capture2e(
        "git", "status", "--porcelain", "--untracked-files=no",
        chdir: path.to_s
      )
      # If we can't even run git here, defer to the existing
      # StandardError swallow — don't synthesize a dirty signal from
      # a broken probe.
      return unless status.success?
      return if out.strip.empty?

      raise DirtyWorktreeError,
        "refusing to refresh #{path}: worktree has uncommitted local changes; " \
        "commit, stash, or remove explicitly before re-ensure\n#{out}"
    end

    def healthy_symlink_to_source?(target, source)
      return false unless target.symlink?
      File.realpath(target) == File.realpath(source)
    rescue Errno::ENOENT
      # Target is a dangling symlink — not healthy.
      false
    end

    # Explicit allowlist of workspace paths that may receive the host
    # app's master.key. Env var NEURAMD_TRUSTED_WORKSPACE_KEYS holds a
    # comma-separated list of absolute paths. A workspace must match
    # one entry by File.realpath to be trusted; any deviation (wrong
    # path, unset env, missing workspace dir) falls through to "not
    # trusted" and the key is not linked.
    def trusted_workspace_for_key?(workspace_path)
      raw = ENV["NEURAMD_TRUSTED_WORKSPACE_KEYS"].to_s
      return false if raw.strip.empty?

      allowed = raw.split(",").map(&:strip).reject(&:empty?)
      workspace_real = File.realpath(workspace_path.to_s)
      allowed.any? do |entry|
        File.realpath(entry) == workspace_real
      rescue Errno::ENOENT
        false
      end
    rescue Errno::ENOENT
      false
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
