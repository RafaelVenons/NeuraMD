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
