# frozen_string_literal: true

require "rails_helper"

RSpec.describe FileImports::SanitizeService do
  describe ".call" do
    context "with good markdown" do
      it "passes through unchanged" do
        md = "# Title\n\nSome content\n\n## Section\n\nMore content"
        report = described_class.call(markdown: md)

        expect(report.usable).to be true
        expect(report.markdown).to eq md
        expect(report.warnings).to be_empty
        expect(report.applied).to be_empty
      end
    end

    context "with blank input" do
      it "returns as-is" do
        report = described_class.call(markdown: "")
        expect(report.usable).to be true
        expect(report.markdown).to eq ""
      end
    end

    # ── Quality gate: CID tokens ──────────────────────────────────────────

    context "with excessive cid tokens (>100)" do
      it "rejects the markdown" do
        cid_lines = (1..120).map { |i| "word(cid:#{i})text" }.join("\n")
        report = described_class.call(markdown: cid_lines)

        expect(report.usable).to be false
        expect(report.warnings.first).to include("encoding")
        expect(report.applied).to be_empty
      end
    end

    context "with high cid token ratio" do
      it "rejects the markdown" do
        md = "a (cid:1) b (cid:2) c (cid:3) d (cid:4) e (cid:5) f (cid:6)"
        report = described_class.call(markdown: md)

        expect(report.usable).to be false
        expect(report.warnings.first).to include("encoding")
      end
    end

    context "with sparse cid tokens (below threshold)" do
      it "strips them and remains usable" do
        filler = (["More content here spanning many words to keep the ratio low enough"] * 50).join("\n")
        md = "# Good Title\n\nSome text with a stray (cid:42) token and (cid:7) another.\n\n#{filler}"
        report = described_class.call(markdown: md)

        expect(report.usable).to be true
        expect(report.markdown).not_to include("(cid:")
        expect(report.applied).to include("strip_sparse_cid_tokens")
        expect(report.warnings.first).to include("Removidos 2 tokens")
      end
    end

    # ── Quality gate: no-space blobs ──────────────────────────────────────

    context "with no-space text blobs" do
      it "rejects the markdown" do
        blob_line = "a" * 100 # 100 chars, no spaces
        normal_line = "this is normal text with spaces that is long enough to be sampled by the detector"
        # Need >30% of long lines without spaces
        md = ([blob_line] * 10 + [normal_line] * 3).join("\n")
        report = described_class.call(markdown: md)

        expect(report.usable).to be false
        expect(report.warnings.first).to include("separacao entre palavras")
      end
    end

    context "with mostly normal text and a few long unspaced lines" do
      it "passes through" do
        normal = "This is a perfectly normal line of text with spaces that exceeds eighty characters in total length here."
        blob = "a" * 100
        md = ([normal] * 20 + [blob]).join("\n")
        report = described_class.call(markdown: md)

        expect(report.usable).to be true
      end
    end

    # ── Form feed conversion ──────────────────────────────────────────────

    context "with form feeds and no headings" do
      it "converts form feeds to H1 root + H2 headings using first line as title" do
        md = "Titulo do Slide 1\n\nConteudo do slide 1.\f" \
             "Titulo do Slide 2\n\nConteudo do slide 2.\f" \
             "Titulo do Slide 3\n\nConteudo do slide 3."
        report = described_class.call(markdown: md, filename: "apresentacao.pdf")

        expect(report.usable).to be true
        expect(report.markdown).to start_with("# apresentacao\n")
        expect(report.markdown).to include("## Titulo do Slide 1")
        expect(report.markdown).to include("## Titulo do Slide 2")
        expect(report.markdown).to include("## Titulo do Slide 3")
        expect(report.markdown).to include("Conteudo do slide 1.")
        expect(report.applied).to include("form_feed_to_headings")
      end
    end

    context "with form feeds and existing headings" do
      it "leaves headings intact" do
        md = "# Real Title\n\nContent\fMore content on next page"
        report = described_class.call(markdown: md)

        expect(report.usable).to be true
        expect(report.markdown).to eq md
        expect(report.applied).not_to include("form_feed_to_headings")
      end
    end

    context "with form feeds but only one page of content" do
      it "does not create headings" do
        md = "\fOnly one page\n\nWith content.\f"
        report = described_class.call(markdown: md)

        expect(report.usable).to be true
        expect(report.markdown).not_to include("##")
      end
    end

    context "with form feed page whose first line is too long" do
      it "uses Slide N as fallback title" do
        long_line = "a" * 130
        md = "#{long_line}\nContent\fSlide Two\nMore content"
        report = described_class.call(markdown: md, filename: "test.pdf")

        expect(report.usable).to be true
        expect(report.markdown).to include("# test\n")
        expect(report.markdown).to include("## Slide 1")
        expect(report.markdown).to include("## Slide Two")
      end
    end

    # ── Bold heading stripping ─────────────────────────────────────────────

    context "with **bold** headings from pymupdf4llm" do
      it "strips bold markers from headings" do
        md = "# **Introduction**\n\nContent\n\n## **Chapter One**\n\nMore content"
        report = described_class.call(markdown: md)

        expect(report.usable).to be true
        expect(report.markdown).to include("# Introduction")
        expect(report.markdown).to include("## Chapter One")
        expect(report.markdown).not_to include("**")
        expect(report.applied).to include("strip_heading_bold")
      end

      it "does not strip bold from body text" do
        md = "# Title\n\nSome **bold** text in body"
        report = described_class.call(markdown: md)

        expect(report.usable).to be true
        expect(report.markdown).to include("Some **bold** text in body")
      end

      it "does not strip partial bold in headings" do
        md = "# Intro to **AI** and ML\n\nContent"
        report = described_class.call(markdown: md)

        expect(report.usable).to be true
        # Only strips when entire heading text is bold-wrapped
        expect(report.markdown).to include("# Intro to **AI** and ML")
      end
    end

    # ── Garbage heading cleanup ───────────────────────────────────────────

    context "with garbage headings" do
      it "removes headings that are empty or just symbols" do
        md = "# Good Title\n\nContent\n\n# $\n\nMore content\n\n## \n\nEven more\n\n##   \n\nFinal"
        report = described_class.call(markdown: md)

        expect(report.usable).to be true
        expect(report.markdown).to include("# Good Title")
        expect(report.markdown).not_to match(/^# \$$/m)
        expect(report.markdown).not_to match(/^## \s*$/m)
        expect(report.applied).to include("clean_garbage_headings")
      end
    end

    context "with valid short headings" do
      it "preserves them" do
        md = "# AI\n\nContent about AI\n\n## ML\n\nMachine learning stuff"
        report = described_class.call(markdown: md)

        expect(report.usable).to be true
        expect(report.markdown).to include("# AI")
        expect(report.markdown).to include("## ML")
      end
    end

    # ── Excessive blanks ──────────────────────────────────────────────────

    context "with excessive blank lines" do
      it "collapses 4+ newlines to 3" do
        md = "Line 1\n\n\n\n\n\nLine 2"
        report = described_class.call(markdown: md)

        expect(report.markdown).to eq "Line 1\n\n\nLine 2"
      end
    end
  end
end
