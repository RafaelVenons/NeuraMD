require "rails_helper"

RSpec.describe Tentacles::BootConfig do
  around do |example|
    original = ENV["NEURAMD_TENTACLE_CWD_ROOTS"]
    example.run
  ensure
    ENV["NEURAMD_TENTACLE_CWD_ROOTS"] = original
  end

  describe ".allowed_cwd_prefixes" do
    it "falls back to the hardcoded default when the env is unset" do
      ENV.delete("NEURAMD_TENTACLE_CWD_ROOTS")
      expect(described_class.allowed_cwd_prefixes).to eq(described_class::DEFAULT_CWD_ALLOWED_PREFIXES)
    end

    it "falls back to the default when the env is empty or whitespace" do
      ENV["NEURAMD_TENTACLE_CWD_ROOTS"] = "   "
      expect(described_class.allowed_cwd_prefixes).to eq(described_class::DEFAULT_CWD_ALLOWED_PREFIXES)
    end

    it "parses a CSV of absolute paths and normalizes trailing slashes" do
      ENV["NEURAMD_TENTACLE_CWD_ROOTS"] = "/home/rafael/projects, /srv/apps/"
      expect(described_class.allowed_cwd_prefixes).to eq(["/home/rafael/projects/", "/srv/apps/"])
    end

    it "ignores empty entries from a malformed CSV" do
      ENV["NEURAMD_TENTACLE_CWD_ROOTS"] = ",/opt/work/,"
      expect(described_class.allowed_cwd_prefixes).to eq(["/opt/work/"])
    end
  end

  describe ".canonicalize_cwd" do
    it "honors a custom prefix set via NEURAMD_TENTACLE_CWD_ROOTS" do
      Dir.mktmpdir("neuramd-cwd-test") do |tmp|
        subdir = File.join(tmp, "child")
        Dir.mkdir(subdir)
        ENV["NEURAMD_TENTACLE_CWD_ROOTS"] = tmp
        canonical, err = described_class.canonicalize_cwd(subdir)
        expect(err).to be_nil
        expect(canonical).to eq(File.realpath(subdir))
      end
    end

    it "rejects paths outside the configured prefixes" do
      Dir.mktmpdir("neuramd-cwd-test") do |tmp|
        ENV["NEURAMD_TENTACLE_CWD_ROOTS"] = tmp
        canonical, err = described_class.canonicalize_cwd("/etc")
        expect(canonical).to be_nil
        expect(err).to include("cwd must be under one of")
      end
    end
  end
end
