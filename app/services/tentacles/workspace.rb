module Tentacles
  # Persistent shared workspace resolver for tentacle sessions.
  #
  # A "workspace" is a named directory under NEURAMD_TENTACLE_WORKSPACE_ROOT
  # holding a git repository that multiple tentacles can share. Each tentacle
  # gets its own git worktree on branch `tentacle/<uuid>`, placed OUTSIDE the
  # shared repo (under ROOT/.tentacle-worktrees/<workspace>/) so the workspace
  # itself stays clean for human collaborators.
  #
  # Names follow a conservative pattern: alphanumeric start, then
  # [a-z0-9_.-]. Leading dots are reserved for the runtime directory
  # (.tentacle-worktrees). No slashes or traversal segments.
  module Workspace
    DEFAULT_ROOT = "/home/rafael/workspaces".freeze
    NAME_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9_.-]*\z/
    WORKTREES_SUBDIR = ".tentacle-worktrees".freeze

    module_function

    def root
      raw = ENV["NEURAMD_TENTACLE_WORKSPACE_ROOT"].to_s
      raw.strip.empty? ? DEFAULT_ROOT : raw
    end

    def resolve(name)
      return [nil, nil] if name.nil? || name.to_s.strip.empty?

      name_str = name.to_s
      return [nil, "invalid workspace name: #{name_str.inspect}"] unless name_str.match?(NAME_PATTERN)

      path = File.join(root, name_str)
      canonical =
        begin
          File.realpath(path)
        rescue Errno::ENOENT, Errno::ENOTDIR
          return [nil, "workspace not found: #{name_str}"]
        end

      # Re-check containment after symlink resolution. Without this, a
      # symlink placed under the shared workspace root could redirect a
      # tentacle's worktree to an arbitrary repo elsewhere on disk,
      # bypassing the workspace whitelist entirely. realpath(root) is
      # computed each call so root-level symlink changes are observed.
      canonical_root =
        begin
          File.realpath(root)
        rescue Errno::ENOENT, Errno::ENOTDIR
          return [nil, "workspace root does not exist: #{root}"]
        end
      root_prefix = canonical_root.end_with?("/") ? canonical_root : "#{canonical_root}/"
      unless canonical.start_with?(root_prefix)
        return [nil, "workspace escapes workspace root: #{name_str}"]
      end

      return [nil, "workspace not found: #{name_str}"] unless File.directory?(canonical)

      # Require `.git` to be a real directory. A `.git` FILE (linked
      # worktrees / submodule-style layouts) can contain
      # `gitdir: <arbitrary path>`, which would cause `git worktree add`
      # to operate on the referenced external repo — bypassing the
      # workspace-root containment enforced above. Workspaces must be
      # standalone main repos so the containment boundary holds through
      # git operations. Linked-worktree workspaces would need gitdir
      # parsing + re-verification to be safe; out of scope here.
      unless File.directory?(File.join(canonical, ".git"))
        return [nil, "workspace is not a git repository: #{name_str}"]
      end

      [canonical, nil]
    end

    def worktree_root_for(name)
      File.join(root, WORKTREES_SUBDIR, name.to_s)
    end
  end
end
