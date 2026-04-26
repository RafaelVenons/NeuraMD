require "rails_helper"
require "open3"

PARSER_PATH = Rails.root.join("deploy/git-hooks/lib/validator_slugs.rb")

require_relative PARSER_PATH.to_s

RSpec.describe ValidatorSlugs do
  describe ".parse_pr_number" do
    it "extracts the PR number from a squash-merge subject" do
      expect(described_class.parse_pr_number("Tiling de tentáculos (Fases 2-5) (#37)\n\nbody")).to eq(37)
    end

    it "extracts the PR number from a merge-commit subject" do
      msg = "Merge pull request #26 from RafaelVenons/fix/auto-refresh-transversal-worktrees\n\nfix: ..."
      expect(described_class.parse_pr_number(msg)).to eq(26)
    end

    it "ignores PR-number mentions inside the body — only the subject counts" do
      # Subject has no (#N); body mentions another PR. Must return nil.
      msg = "Direct fix\n\nRelates to (#99). Not a PR landing.\n"
      expect(described_class.parse_pr_number(msg)).to be_nil
    end

    it "returns nil for direct pushes with no PR tag" do
      expect(described_class.parse_pr_number("Whitelist ~/git-mirrors in tentacle sandbox")).to be_nil
    end

    it "returns nil for nil/empty input" do
      expect(described_class.parse_pr_number(nil)).to be_nil
      expect(described_class.parse_pr_number("")).to be_nil
    end
  end

  describe ".parse_slugs" do
    it "extracts backticked slugs from bullet items in the validator section" do
      body = <<~MD
        ## Summary

        Stuff.

        ## Validar pós-deploy com:

        - `especialista-neuramd` — confirmar smoke
        - `sentinela-de-deploy` — reativar
      MD
      expect(described_class.parse_slugs(body)).to eq(%w[especialista-neuramd sentinela-de-deploy])
    end

    it "extracts plain (non-backticked) slugs too" do
      body = <<~MD
        ## Validar pós-deploy com:

        - especialista-neuramd — algo
        - ux-ui
      MD
      expect(described_class.parse_slugs(body)).to eq(%w[especialista-neuramd ux-ui])
    end

    it "accepts asterisk bullets as well as dash bullets" do
      body = <<~MD
        ## Validar pós-deploy com:

        * `especialista-neuramd`
        * `ux-ui`
      MD
      expect(described_class.parse_slugs(body)).to eq(%w[especialista-neuramd ux-ui])
    end

    it "stops at the next H1 or H2 — not at H3" do
      body = <<~MD
        ## Validar pós-deploy com:

        - `slug-a`

        ### Sub-seção

        - `slug-b`

        ## Outra seção

        - `slug-c`
      MD
      # slug-c is in a different H2 and must NOT be picked up.
      expect(described_class.parse_slugs(body)).to eq(%w[slug-a slug-b])
    end

    it "deduplicates slugs that appear twice in the section" do
      body = <<~MD
        ## Validar pós-deploy com:

        - `especialista-neuramd` — first mention
        - `especialista-neuramd` — duplicated by accident
        - `ux-ui`
      MD
      expect(described_class.parse_slugs(body)).to eq(%w[especialista-neuramd ux-ui])
    end

    it "caps results at SLUG_LIMIT to bound the wake budget" do
      bullets = (1..(ValidatorSlugs::SLUG_LIMIT + 5)).map { |i| "- `slug-#{i}`" }.join("\n")
      body = "## Validar pós-deploy com:\n\n#{bullets}\n"
      result = described_class.parse_slugs(body)
      expect(result.length).to eq(ValidatorSlugs::SLUG_LIMIT)
      expect(result.first).to eq("slug-1")
      expect(result.last).to eq("slug-#{ValidatorSlugs::SLUG_LIMIT}")
    end

    it "returns [] when the section header is absent" do
      body = "## Summary\n\nNothing here.\n"
      expect(described_class.parse_slugs(body)).to eq([])
    end

    it "accepts the unaccented header variant (pos-deploy)" do
      body = "## Validar pos-deploy com:\n\n- `especialista-neuramd`\n"
      expect(described_class.parse_slugs(body)).to eq(%w[especialista-neuramd])
    end

    it "is case-insensitive on the header" do
      body = "## VALIDAR PÓS-DEPLOY COM:\n\n- `especialista-neuramd`\n"
      expect(described_class.parse_slugs(body)).to eq(%w[especialista-neuramd])
    end

    it "ignores bullets outside the validator section" do
      body = <<~MD
        ## Test plan

        - `not-a-validator-slug`

        ## Validar pós-deploy com:

        - `especialista-neuramd`
      MD
      expect(described_class.parse_slugs(body)).to eq(%w[especialista-neuramd])
    end

    it "returns [] for nil or empty input" do
      expect(described_class.parse_slugs(nil)).to eq([])
      expect(described_class.parse_slugs("")).to eq([])
    end
  end

  describe "CLI" do
    # Run the script as a subprocess to verify the deploy host can call
    # it without the Rails bundle context. The post-receive hook runs
    # `ruby <parser>` after `unset GIT_DIR` and outside any `bundle exec`
    # — so the spec mirrors that by clearing the bundler env vars
    # (BUNDLE_GEMFILE / RUBYOPT) that rspec inherits from `bundle exec`.
    def run_cli(verb, stdin_data)
      Bundler.with_unbundled_env do
        Open3.capture3({}, "ruby", PARSER_PATH.to_s, verb, stdin_data: stdin_data)
      end
    end

    it "parse-slugs prints one slug per line on stdout, exits 0" do
      body = "## Validar pós-deploy com:\n\n- `especialista-neuramd`\n- `ux-ui`\n"
      stdout, stderr, status = run_cli("parse-slugs", body)
      expect(status.exitstatus).to eq(0), "stderr was: #{stderr}"
      expect(stdout.lines.map(&:chomp)).to eq(%w[especialista-neuramd ux-ui])
    end

    it "parse-pr-number prints the number and exits 0 on a tagged subject" do
      stdout, _stderr, status = run_cli("parse-pr-number", "Some title (#42)\n\nbody\n")
      expect(status.exitstatus).to eq(0)
      expect(stdout.chomp).to eq("42")
    end

    it "parse-pr-number exits 1 with no stdout when the subject has no PR tag" do
      stdout, _stderr, status = run_cli("parse-pr-number", "Direct push\n")
      expect(status.exitstatus).to eq(1)
      expect(stdout).to be_empty
    end

    it "exits 2 with usage on unknown verb" do
      _stdout, stderr, status = run_cli("frobnicate", "")
      expect(status.exitstatus).to eq(2)
      expect(stderr).to include("usage:")
    end
  end
end
