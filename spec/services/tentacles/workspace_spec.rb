require "rails_helper"
require "fileutils"
require "tmpdir"
require "open3"

RSpec.describe Tentacles::Workspace do
  let(:sandbox) { Dir.mktmpdir("neuramd-workspace-spec-") }

  around do |example|
    original = ENV["NEURAMD_TENTACLE_WORKSPACE_ROOT"]
    ENV["NEURAMD_TENTACLE_WORKSPACE_ROOT"] = sandbox
    example.run
  ensure
    ENV["NEURAMD_TENTACLE_WORKSPACE_ROOT"] = original
  end

  after { FileUtils.remove_entry(sandbox) if File.directory?(sandbox) }

  def make_repo(name)
    path = File.join(sandbox, name)
    FileUtils.mkdir_p(path)
    out, status = Open3.capture2e(
      {"GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_SYSTEM" => "/dev/null"},
      "git", "init", "--quiet", "--initial-branch=main", chdir: path
    )
    raise "git init failed: #{out}" unless status.success?
    path
  end

  describe ".root" do
    it "returns the env value when set" do
      expect(described_class.root).to eq(sandbox)
    end

    it "falls back to DEFAULT_ROOT when the env is blank" do
      ENV["NEURAMD_TENTACLE_WORKSPACE_ROOT"] = "   "
      expect(described_class.root).to eq(described_class::DEFAULT_ROOT)
    end
  end

  describe ".resolve" do
    it "returns [nil, nil] for blank input (opt-out path)" do
      expect(described_class.resolve(nil)).to eq([nil, nil])
      expect(described_class.resolve("")).to eq([nil, nil])
      expect(described_class.resolve("   ")).to eq([nil, nil])
    end

    it "rejects names containing path separators" do
      path, err = described_class.resolve("foo/bar")
      expect(path).to be_nil
      expect(err).to match(/invalid workspace name/i)
    end

    it "rejects names with traversal segments" do
      path, err = described_class.resolve("..")
      expect(path).to be_nil
      expect(err).to match(/invalid workspace name/i)
    end

    it "rejects names starting with a dot (hidden dirs reserved for runtime)" do
      path, err = described_class.resolve(".tentacle-worktrees")
      expect(path).to be_nil
      expect(err).to match(/invalid workspace name/i)
    end

    it "rejects nonexistent workspaces" do
      path, err = described_class.resolve("missing")
      expect(path).to be_nil
      expect(err).to match(/workspace not found/i)
    end

    it "rejects directories that are not git repositories" do
      FileUtils.mkdir_p(File.join(sandbox, "plain"))
      path, err = described_class.resolve("plain")
      expect(path).to be_nil
      expect(err).to match(/not a git repository/i)
    end

    it "returns the canonical path for a valid workspace" do
      expected = make_repo("valid")
      path, err = described_class.resolve("valid")
      expect(err).to be_nil
      expect(path).to eq(File.realpath(expected))
    end

    it "accepts names with underscores, hyphens and dots after the first character" do
      make_repo("neuramd_v2")
      make_repo("my-project")
      make_repo("foo.bar")

      expect(described_class.resolve("neuramd_v2").last).to be_nil
      expect(described_class.resolve("my-project").last).to be_nil
      expect(described_class.resolve("foo.bar").last).to be_nil
    end

    it "rejects a symlink entry that escapes the workspace root" do
      external = Dir.mktmpdir("ws-spec-escape-")
      external_repo = File.join(external, "rogue")
      FileUtils.mkdir_p(File.join(external_repo, ".git"))

      File.symlink(external_repo, File.join(sandbox, "escaped"))

      path, err = described_class.resolve("escaped")
      expect(path).to be_nil
      expect(err).to match(/escapes workspace root/i)
    ensure
      FileUtils.remove_entry(external) if external && File.directory?(external)
    end

    it "accepts an intra-root symlink that still resolves under the workspace root" do
      target = make_repo("actual")
      File.symlink(target, File.join(sandbox, "alias"))

      path, err = described_class.resolve("alias")
      expect(err).to be_nil
      expect(path).to eq(File.realpath(target))
    end
  end

  describe ".worktree_root_for" do
    it "returns a namespaced path under the workspace root" do
      expect(described_class.worktree_root_for("neuramd"))
        .to eq(File.join(sandbox, ".tentacle-worktrees", "neuramd"))
    end

    it "does not create the directory" do
      described_class.worktree_root_for("neuramd")
      expect(File.exist?(File.join(sandbox, ".tentacle-worktrees"))).to be(false)
    end
  end
end
