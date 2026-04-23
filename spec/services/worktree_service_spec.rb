require "rails_helper"
require "fileutils"
require "tmpdir"
require "open3"

RSpec.describe WorktreeService do
  let(:sandbox) { Dir.mktmpdir("neuramd-worktree-spec-") }
  let(:repo_root) { Pathname.new(sandbox).join("repo") }
  let(:tentacle_id) { "11111111-2222-3333-4444-555555555555" }

  before do
    FileUtils.mkdir_p(repo_root)
    run_git("init", "--initial-branch=main")
    run_git("config", "user.email", "spec@neuramd.test")
    run_git("config", "user.name", "Spec")
    File.write(repo_root.join("README.md"), "hello\n")
    run_git("add", ".")
    run_git("commit", "-m", "initial")
  end

  after { FileUtils.remove_entry(sandbox) if File.directory?(sandbox) }

  def run_git(*args)
    out, status = Open3.capture2e({ "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_SYSTEM" => "/dev/null" },
      "git", *args, chdir: repo_root.to_s)
    raise "git #{args.inspect} failed: #{out}" unless status.success?
    out
  end

  describe ".ensure" do
    it "creates a worktree at tmp/tentacles/<id> with a dedicated branch" do
      path = described_class.ensure(tentacle_id: tentacle_id, repo_root: repo_root)

      expect(path).to eq(repo_root.join("tmp/tentacles", tentacle_id).to_s)
      expect(File.directory?(path)).to be(true)
      expect(File.read(File.join(path, "README.md"))).to eq("hello\n")

      listing = run_git("worktree", "list", "--porcelain")
      expect(listing).to include(path)
      expect(listing).to include("branch refs/heads/tentacle/#{tentacle_id}")
    end

    it "is idempotent when the worktree already exists" do
      first = described_class.ensure(tentacle_id: tentacle_id, repo_root: repo_root)
      second = described_class.ensure(tentacle_id: tentacle_id, repo_root: repo_root)

      expect(second).to eq(first)
      listing = run_git("worktree", "list", "--porcelain")
      expect(listing.scan("worktree #{first}").size).to eq(1)
    end

    it "links gitignored runtime paths from the main repo into the worktree" do
      FileUtils.mkdir_p(repo_root.join("vendor/bundle/ruby/3.3.0"))
      File.write(repo_root.join("vendor/bundle/ruby/3.3.0/marker"), "installed\n")
      FileUtils.mkdir_p(repo_root.join(".bundle"))
      File.write(repo_root.join(".bundle/config"), "BUNDLE_PATH: \"vendor/bundle\"\n")
      FileUtils.mkdir_p(repo_root.join("config"))
      File.write(repo_root.join("config/master.key"), "deadbeef\n")

      path = described_class.ensure(tentacle_id: tentacle_id, repo_root: repo_root)

      [
        ["vendor/bundle", "vendor/bundle"],
        [".bundle", ".bundle"],
        ["config/master.key", "config/master.key"]
      ].each do |source_rel, target_rel|
        target = File.join(path, target_rel)
        expect(File.symlink?(target)).to be(true), "expected #{target_rel} to be a symlink"
        expect(File.realpath(target)).to eq(repo_root.join(source_rel).realpath.to_s)
      end
      expect(File.read(File.join(path, "vendor/bundle/ruby/3.3.0/marker"))).to eq("installed\n")
      expect(File.read(File.join(path, "config/master.key"))).to eq("deadbeef\n")
    end

    it "skips linking when the main repo has no runtime paths to share" do
      path = described_class.ensure(tentacle_id: tentacle_id, repo_root: repo_root)

      expect(File.exist?(File.join(path, "vendor/bundle"))).to be(false)
      expect(File.exist?(File.join(path, ".bundle"))).to be(false)
      expect(File.exist?(File.join(path, "config/master.key"))).to be(false)
    end

    it "recovers when the directory exists but is not registered as a worktree" do
      orphan_path = repo_root.join("tmp/tentacles", tentacle_id)
      FileUtils.mkdir_p(orphan_path)
      File.write(orphan_path.join("stale.txt"), "leftover")

      path = described_class.ensure(tentacle_id: tentacle_id, repo_root: repo_root)

      expect(path).to eq(orphan_path.to_s)
      listing = run_git("worktree", "list", "--porcelain")
      expect(listing).to include(path)
      expect(File.exist?(orphan_path.join("README.md"))).to be(true)
    end
  end

  describe ".remove" do
    it "removes the worktree and its branch" do
      path = described_class.ensure(tentacle_id: tentacle_id, repo_root: repo_root)
      expect(File.directory?(path)).to be(true)

      described_class.remove(tentacle_id: tentacle_id, repo_root: repo_root)

      expect(File.directory?(path)).to be(false)
      listing = run_git("worktree", "list", "--porcelain")
      expect(listing).not_to include(path)
      branches = run_git("branch", "--list", "tentacle/#{tentacle_id}")
      expect(branches).to be_empty.or eq("\n")
    end

    it "is a no-op when the worktree does not exist" do
      expect {
        described_class.remove(tentacle_id: tentacle_id, repo_root: repo_root)
      }.not_to raise_error
    end
  end

  describe ".path_for" do
    it "returns the conventional path without touching the filesystem" do
      path = described_class.path_for(tentacle_id: tentacle_id, repo_root: repo_root)
      expect(path).to eq(repo_root.join("tmp/tentacles", tentacle_id).to_s)
      expect(File.exist?(path)).to be(false)
    end

    it "returns <worktree_root>/<id> when an explicit worktree_root is given" do
      custom = Pathname.new(sandbox).join("wt-root")
      path = described_class.path_for(
        tentacle_id: tentacle_id,
        repo_root: repo_root,
        worktree_root: custom
      )
      expect(path).to eq(custom.join(tentacle_id).to_s)
    end
  end

  describe ".ensure with worktree_root:" do
    let(:worktree_root) { Pathname.new(sandbox).join(".tentacle-worktrees", "neuramd") }

    it "creates the worktree outside the repo_root" do
      path = described_class.ensure(
        tentacle_id: tentacle_id,
        repo_root: repo_root,
        worktree_root: worktree_root
      )

      expect(path).to eq(worktree_root.join(tentacle_id).to_s)
      expect(File.directory?(path)).to be(true)
      expect(path).not_to start_with(repo_root.to_s)

      listing = run_git("worktree", "list", "--porcelain")
      expect(listing).to include(path)
      expect(listing).to include("branch refs/heads/tentacle/#{tentacle_id}")
    end

    it "is idempotent across calls" do
      first = described_class.ensure(
        tentacle_id: tentacle_id, repo_root: repo_root, worktree_root: worktree_root
      )
      second = described_class.ensure(
        tentacle_id: tentacle_id, repo_root: repo_root, worktree_root: worktree_root
      )
      expect(second).to eq(first)
      listing = run_git("worktree", "list", "--porcelain")
      expect(listing.scan("worktree #{first}").size).to eq(1)
    end
  end

  describe ".ensure with link_shared: false" do
    let(:worktree_root) { Pathname.new(sandbox).join(".tentacle-worktrees", "neuramd") }

    before do
      FileUtils.mkdir_p(repo_root.join("vendor/bundle"))
      File.write(repo_root.join("vendor/bundle/marker"), "installed\n")
      FileUtils.mkdir_p(repo_root.join(".bundle"))
      File.write(repo_root.join(".bundle/config"), "x\n")
      FileUtils.mkdir_p(repo_root.join("config"))
      File.write(repo_root.join("config/master.key"), "deadbeef\n")
    end

    it "does not symlink SHARED_PATHS from the repo_root" do
      path = described_class.ensure(
        tentacle_id: tentacle_id,
        repo_root: repo_root,
        worktree_root: worktree_root,
        link_shared: false
      )

      ["vendor/bundle", ".bundle", "config/master.key"].each do |rel|
        target = File.join(path, rel)
        expect(File.exist?(target)).to be(false), "expected #{rel} to be absent"
        expect(File.symlink?(target)).to be(false), "expected #{rel} to be absent (not a symlink)"
      end
    end

    it "still links when link_shared is true (default)" do
      path = described_class.ensure(
        tentacle_id: tentacle_id,
        repo_root: repo_root,
        worktree_root: worktree_root
      )

      expect(File.symlink?(File.join(path, "vendor/bundle"))).to be(true)
    end
  end

  describe ".ensure runtime secrets for Rails-app workspaces" do
    let(:workspace_root) { Pathname.new(sandbox).join(".tentacle-worktrees", "railsy") }
    let(:rails_root) { Pathname.new(Dir.mktmpdir("neuramd-rails-runtime-")) }

    before do
      # Simulate the current process's Rails.root (the running neuramd-web)
      # holding the authoritative master.key. WorktreeService symlinks from
      # this location when preparing a Rails-app workspace or worktree.
      FileUtils.mkdir_p(rails_root.join("config"))
      File.write(rails_root.join("config/master.key"), "abcdef1234567890\n")
      allow(Rails).to receive(:root).and_return(rails_root)

      # Rails.root needs its own git repo with the same `origin` URL as
      # the workspace — same_project? uses `git remote get-url origin`
      # on both sides to decide whether sharing the key is safe.
      Open3.capture2e({"GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_SYSTEM" => "/dev/null"},
        "git", "init", "--quiet", "--initial-branch=main", chdir: rails_root.to_s)
      Open3.capture2e("git", "remote", "add", "origin", "https://example.test/neuramd.git", chdir: rails_root.to_s)

      run_git("remote", "add", "origin", "https://example.test/neuramd.git")

      # Workspace-as-Rails-app: has credentials.yml.enc committed but no
      # master.key (the gitignored file the symlink provides). Must be
      # committed so every worktree checkout also has it.
      FileUtils.mkdir_p(repo_root.join("config"))
      File.write(repo_root.join("config/credentials.yml.enc"), "encrypted\n")
      run_git("add", "config/credentials.yml.enc")
      run_git("commit", "-m", "add credentials.yml.enc")
    end

    after { FileUtils.remove_entry(rails_root) if File.directory?(rails_root) }

    it "symlinks master.key into the worktree even when link_shared is false" do
      path = described_class.ensure(
        tentacle_id: tentacle_id,
        repo_root: repo_root,
        worktree_root: workspace_root,
        link_shared: false
      )

      target = File.join(path, "config/master.key")
      expect(File.symlink?(target)).to be(true), "master.key should be symlinked even with link_shared: false"
      expect(File.read(target)).to eq("abcdef1234567890\n")
      expect(File.realpath(target)).to eq(rails_root.join("config/master.key").to_s)
    end

    it "leaves the backing workspace repo untouched (scope limited to worktree)" do
      described_class.ensure(
        tentacle_id: tentacle_id,
        repo_root: repo_root,
        worktree_root: workspace_root,
        link_shared: false
      )

      # master.key in the workspace itself is NOT created — avoids
      # persistent secret exposure in a human-facing clone that
      # `remove` would leave behind.
      workspace_key = repo_root.join("config/master.key")
      expect(workspace_key.exist?).to be(false)
      expect(workspace_key.symlink?).to be(false)
    end

    it "reconciles the symlink on repeat ensure calls for an already-registered worktree" do
      # First call creates the worktree + symlink.
      path = described_class.ensure(
        tentacle_id: tentacle_id,
        repo_root: repo_root,
        worktree_root: workspace_root,
        link_shared: false
      )
      key_target = File.join(path, "config/master.key")
      expect(File.symlink?(key_target)).to be(true)

      # Simulate: manual rm of the symlink (or a pre-fix worktree that
      # never had it). The worktree IS still registered with git.
      FileUtils.rm(key_target)
      expect(File.exist?(key_target)).to be(false)

      # Second call must reconcile instead of short-circuiting at the
      # `registered?` early return.
      described_class.ensure(
        tentacle_id: tentacle_id,
        repo_root: repo_root,
        worktree_root: workspace_root,
        link_shared: false
      )
      expect(File.symlink?(key_target)).to be(true)
      expect(File.realpath(key_target)).to eq(rails_root.join("config/master.key").to_s)
    end

    it "is idempotent when the symlink already exists" do
      FileUtils.mkdir_p(repo_root.join("config"))
      File.symlink(rails_root.join("config/master.key").to_s, repo_root.join("config/master.key").to_s)

      expect {
        described_class.ensure(
          tentacle_id: tentacle_id,
          repo_root: repo_root,
          worktree_root: workspace_root,
          link_shared: false
        )
      }.not_to raise_error
    end

    it "does not overwrite an existing real master.key inside the worktree" do
      path = described_class.ensure(
        tentacle_id: tentacle_id,
        repo_root: repo_root,
        worktree_root: workspace_root,
        link_shared: false
      )
      worktree_key = File.join(path, "config/master.key")

      # Replace the symlink with a real file — e.g. agent wrote a
      # different local key for experimental use.
      FileUtils.rm(worktree_key)
      File.write(worktree_key, "worktree-owned-key\n")

      described_class.ensure(
        tentacle_id: tentacle_id,
        repo_root: repo_root,
        worktree_root: workspace_root,
        link_shared: false
      )

      expect(File.symlink?(worktree_key)).to be(false)
      expect(File.read(worktree_key)).to eq("worktree-owned-key\n")
    end

    it "skips linking when the workspace is not a Rails app (no credentials.yml.enc)" do
      FileUtils.rm(repo_root.join("config/credentials.yml.enc"))
      run_git("add", "config/credentials.yml.enc")
      run_git("commit", "-m", "remove credentials.yml.enc")

      path = described_class.ensure(
        tentacle_id: tentacle_id,
        repo_root: repo_root,
        worktree_root: workspace_root,
        link_shared: false
      )

      expect(File.exist?(File.join(path, "config/master.key"))).to be(false)
      expect(File.exist?(repo_root.join("config/master.key"))).to be(false)
    end

    it "skips when the running Rails.root has no master.key" do
      FileUtils.rm(rails_root.join("config/master.key"))

      path = described_class.ensure(
        tentacle_id: tentacle_id,
        repo_root: repo_root,
        worktree_root: workspace_root,
        link_shared: false
      )

      expect(File.exist?(File.join(path, "config/master.key"))).to be(false)
    end

    it "does not link into a Rails workspace from a DIFFERENT origin (foreign project)" do
      # Point the workspace's origin at some other repo. master.key must
      # NOT be symlinked — it would leak host credentials into an
      # unrelated Rails app, and decryption against that app's
      # credentials.yml.enc would fail anyway.
      Open3.capture2e("git", "remote", "set-url", "origin", "https://example.test/different-project.git", chdir: repo_root.to_s)

      path = described_class.ensure(
        tentacle_id: tentacle_id,
        repo_root: repo_root,
        worktree_root: workspace_root,
        link_shared: false
      )

      expect(File.exist?(repo_root.join("config/master.key"))).to be(false)
      expect(File.exist?(File.join(path, "config/master.key"))).to be(false)
    end

    it "does not link when the workspace has no origin remote" do
      Open3.capture2e("git", "remote", "remove", "origin", chdir: repo_root.to_s)

      path = described_class.ensure(
        tentacle_id: tentacle_id,
        repo_root: repo_root,
        worktree_root: workspace_root,
        link_shared: false
      )

      expect(File.exist?(repo_root.join("config/master.key"))).to be(false)
      expect(File.exist?(File.join(path, "config/master.key"))).to be(false)
    end

    it "treats ssh and https origin URLs for the same repo as the same project" do
      Open3.capture2e("git", "remote", "set-url", "origin", "https://github.com/RafaelVenons/neuramd.git", chdir: repo_root.to_s)
      Open3.capture2e("git", "remote", "set-url", "origin", "git@github.com:RafaelVenons/neuramd.git", chdir: rails_root.to_s)

      path = described_class.ensure(
        tentacle_id: tentacle_id,
        repo_root: repo_root,
        worktree_root: workspace_root,
        link_shared: false
      )

      expect(File.symlink?(File.join(path, "config/master.key"))).to be(true)
    end

    it "normalizes trailing .git and user-prefixed https URLs" do
      Open3.capture2e("git", "remote", "set-url", "origin", "https://token@github.com/RafaelVenons/neuramd", chdir: repo_root.to_s)
      Open3.capture2e("git", "remote", "set-url", "origin", "git@github.com:RafaelVenons/neuramd.git", chdir: rails_root.to_s)

      path = described_class.ensure(
        tentacle_id: tentacle_id,
        repo_root: repo_root,
        worktree_root: workspace_root,
        link_shared: false
      )

      expect(File.symlink?(File.join(path, "config/master.key"))).to be(true)
    end

    it "replaces a dangling symlink that points at a stale source path" do
      path = described_class.ensure(
        tentacle_id: tentacle_id,
        repo_root: repo_root,
        worktree_root: workspace_root,
        link_shared: false
      )
      key_target = File.join(path, "config/master.key")
      expect(File.symlink?(key_target)).to be(true)

      # Simulate: previous Rails.root moved/was replaced. The worktree's
      # master.key symlink is now dangling (points nowhere resolvable)
      # — re-ensure must repair by pointing at the current Rails.root.
      stale_source = File.join(Dir.tmpdir, "stale-neuramd-#{SecureRandom.hex(4)}", "config/master.key")
      FileUtils.rm(key_target)
      FileUtils.mkdir_p(File.dirname(key_target))
      File.symlink(stale_source, key_target)
      dangling = begin
        File.realpath(key_target)
      rescue Errno::ENOENT
        nil
      end
      expect(dangling).to be_nil

      described_class.ensure(
        tentacle_id: tentacle_id,
        repo_root: repo_root,
        worktree_root: workspace_root,
        link_shared: false
      )

      expect(File.symlink?(key_target)).to be(true)
      expect(File.realpath(key_target)).to eq(rails_root.join("config/master.key").to_s)
    end

    it "replaces a symlink that points at a DIFFERENT (non-current) master.key path" do
      path = described_class.ensure(
        tentacle_id: tentacle_id,
        repo_root: repo_root,
        worktree_root: workspace_root,
        link_shared: false
      )
      key_target = File.join(path, "config/master.key")

      # Replace with a symlink to a DIFFERENT existing file — simulates
      # a previous deploy's Rails.root that is still on disk but is
      # no longer authoritative.
      other_source = File.join(rails_root, "config/old-master.key")
      File.write(other_source, "old-deploy-key\n")
      FileUtils.rm(key_target)
      File.symlink(other_source, key_target)

      described_class.ensure(
        tentacle_id: tentacle_id,
        repo_root: repo_root,
        worktree_root: workspace_root,
        link_shared: false
      )

      expect(File.realpath(key_target)).to eq(rails_root.join("config/master.key").to_s)
    end

    it "recovers when a concurrent spawn creates the symlink mid-call (EEXIST race)" do
      # Simulate: our check-then-create loses the race — File.exist?
      # reports false, but another process creates the file before our
      # File.symlink call. The Errno::EEXIST rescue must swallow cleanly
      # since the desired end-state (symlink present) is already met.
      allow(File).to receive(:symlink).and_wrap_original do |orig, src, dst|
        orig.call(src, dst)
        raise Errno::EEXIST
      end

      path = nil
      expect {
        path = described_class.ensure(
          tentacle_id: tentacle_id,
          repo_root: repo_root,
          worktree_root: workspace_root,
          link_shared: false
        )
      }.not_to raise_error

      expect(File.symlink?(File.join(path, "config/master.key"))).to be(true)
    end
  end

  describe ".remove with worktree_root:" do
    let(:worktree_root) { Pathname.new(sandbox).join(".tentacle-worktrees", "neuramd") }

    it "removes the worktree and branch when placed outside the repo" do
      path = described_class.ensure(
        tentacle_id: tentacle_id, repo_root: repo_root, worktree_root: worktree_root
      )
      expect(File.directory?(path)).to be(true)

      described_class.remove(
        tentacle_id: tentacle_id, repo_root: repo_root, worktree_root: worktree_root
      )

      expect(File.directory?(path)).to be(false)
      listing = run_git("worktree", "list", "--porcelain")
      expect(listing).not_to include(path)
      branches = run_git("branch", "--list", "tentacle/#{tentacle_id}")
      expect(branches).to be_empty.or eq("\n")
    end
  end
end
