# frozen_string_literal: true

require "rails_helper"

RSpec.describe FileImports::SplitSuggestionService do
  describe ".call" do
    context "with well-structured markdown" do
      it "returns one suggestion per section" do
        md = <<~MD
          # Book Title

          Introduction text.

          ## Chapter 1

          #{(["Content line."] * 15).join("\n")}

          ## Chapter 2

          #{(["More content."] * 15).join("\n")}
        MD

        suggestions = described_class.call(markdown: md, split_level: -1)

        expect(suggestions.size).to eq(3)
        expect(suggestions.map(&:title)).to eq(["Book Title", "Chapter 1", "Chapter 2"])
        suggestions.each do |s|
          expect(s.start_line).to be >= 0
          expect(s.end_line).to be >= s.start_line
          expect(s.line_count).to be > 0
        end
      end
    end

    context "with no headings" do
      it "returns a single suggestion using filename" do
        md = "Just plain text.\n\nMore text."
        suggestions = described_class.call(markdown: md, filename: "my_document.pdf")

        expect(suggestions.size).to eq(1)
        expect(suggestions.first.title).to eq("my document")
        expect(suggestions.first.start_line).to eq(0)
      end
    end

    context "with anemic sections (<10 content lines)" do
      it "merges anemic sections into previous sibling" do
        md = <<~MD
          # Root

          Intro.

          ## Long Chapter

          #{(["Content."] * 15).join("\n")}

          ## Short Section

          Just two lines.
          And another.

          ## Another Long

          #{(["More content."] * 15).join("\n")}
        MD

        suggestions = described_class.call(markdown: md, split_level: -1)

        titles = suggestions.map(&:title)
        expect(titles).not_to include("Short Section")
        expect(titles).to include("Long Chapter", "Another Long")
      end

      it "does not merge root sections (level 1)" do
        md = "# Only Title\n\nShort body."
        suggestions = described_class.call(markdown: md, split_level: -1)

        expect(suggestions.size).to eq(1)
        expect(suggestions.first.title).to eq("Only Title")
      end
    end

    context "with split_level 0 (no fragmentation)" do
      it "returns a single suggestion" do
        md = "# Root\n\nIntro.\n\n## Ch1\n\nContent.\n\n## Ch2\n\nMore."
        suggestions = described_class.call(markdown: md, split_level: 0)

        expect(suggestions.size).to eq(1)
        expect(suggestions.first.title).to eq("Root")
      end
    end

    context "with split_level 2" do
      it "only suggests H1 and H2 sections" do
        md = <<~MD
          # Book

          Intro.

          ## Part 1

          #{(["Content."] * 12).join("\n")}

          ### Detail

          Sub content.

          ## Part 2

          #{(["More."] * 12).join("\n")}
        MD

        suggestions = described_class.call(markdown: md, split_level: 2)
        titles = suggestions.map(&:title)

        expect(titles).to include("Book", "Part 1", "Part 2")
        expect(titles).not_to include("Detail")
      end
    end

    context "with blank markdown" do
      it "returns a single suggestion" do
        suggestions = described_class.call(markdown: "", filename: "empty.pdf")

        expect(suggestions.size).to eq(1)
        expect(suggestions.first.title).to eq("empty")
      end
    end

    context "line ranges" do
      it "covers the entire document" do
        md = "# Title\n\nBody line 1.\nBody line 2.\n\n## Section\n\nSection content."
        suggestions = described_class.call(markdown: md, split_level: -1)

        expect(suggestions.first.start_line).to eq(0)
        expect(suggestions.last.end_line).to eq(md.lines.size - 1)
      end
    end
  end
end
