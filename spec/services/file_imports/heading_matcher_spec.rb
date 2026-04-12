# frozen_string_literal: true

require "rails_helper"

RSpec.describe FileImports::HeadingMatcher do
  # Build a minimal entry struct compatible with FileImports::TocDetector::Entry
  def entry(level:, number: nil, title:, page: nil, source_line: 0)
    FileImports::TocDetector::Entry.new(
      level: level, number: number, title: title, page: page,
      raw_line: title, source_line: source_line
    )
  end

  describe ".call" do
    context "tier 1: exact normalized equality" do
      it "matches a # heading by title" do
        md = <<~MD
          # Book

          ## Introduction

          Body.
        MD
        entries = [entry(level: 1, title: "Introduction")]

        result = described_class.call(markdown: md, entries: entries)
        expect(result.first[:body_line]).to eq(2)
        expect(result.first[:confidence]).to eq(1.0)
      end
    end

    context "tier 2: bi-directional substring" do
      it "matches when body heading adds a subtitle" do
        md = <<~MD
          ## Roadmap da Evolução da IA Do Cálculo à Autonomia

          Body.
        MD
        entries = [entry(level: 1, title: "Roadmap da Evolução da IA")]

        result = described_class.call(markdown: md, entries: entries)
        expect(result.first[:body_line]).to eq(0)
        expect(result.first[:confidence]).to eq(0.9)
      end
    end

    context "tier 3: number prefix match" do
      it "matches '2.1 Foo' TOC entry to body heading with same number" do
        md = <<~MD
          ## 2.1 Exemplo de Problema

          Body.
        MD
        entries = [entry(level: 2, number: "2.1", title: "Exemplo")]

        result = described_class.call(markdown: md, entries: entries)
        expect(result.first[:body_line]).to eq(0)
      end
    end

    context "tier 4: token Jaccard threshold" do
      it "matches when titles share most tokens" do
        md = <<~MD
          ## Busca heurística em espaços de estados

          Body.
        MD
        entries = [entry(level: 1, title: "Busca heurística em espaços")]

        result = described_class.call(markdown: md, entries: entries)
        expect(result.first[:body_line]).to eq(0)
      end
    end

    context "bold-wrapped body heading" do
      it "matches **Title** as level-2 heading" do
        md = <<~MD
          **Introduction**

          Body.
        MD
        entries = [entry(level: 1, title: "Introduction")]

        result = described_class.call(markdown: md, entries: entries)
        expect(result.first[:body_line]).to eq(0)
        expect(result.first[:body_level]).to eq(2)
      end
    end

    context "plain-text CHAPTER N heading (Luger-style)" do
      it "matches uppercase CHAPTER lines without #" do
        md = <<~MD
          CHAPTER 1 AI: HISTORY AND APPLICATIONS

          Body.
        MD
        entries = [entry(level: 1, number: "1", title: "AI: History and Applications")]

        result = described_class.call(markdown: md, entries: entries)
        expect(result.first[:body_line]).to eq(0)
      end
    end

    context "no match" do
      it "returns body_line: nil and confidence 0.0" do
        md = "## Completely unrelated heading\n\nBody.\n"
        entries = [entry(level: 1, title: "Nothing like this exists")]

        result = described_class.call(markdown: md, entries: entries)
        expect(result.first[:body_line]).to be_nil
        expect(result.first[:confidence]).to eq(0.0)
      end
    end

    context "skip_before_line" do
      it "ignores headings inside the TOC region" do
        md = <<~MD
          ## Contents

          ## Introduction

          ## Introduction

          Body.
        MD
        entries = [entry(level: 1, title: "Introduction")]

        result = described_class.call(markdown: md, entries: entries, skip_before_line: 2)
        expect(result.first[:body_line]).to eq(4)
      end
    end

    context "one body heading per entry (no reuse)" do
      it "assigns distinct body lines when multiple entries share a title stem" do
        md = <<~MD
          ## Introduction

          body 1

          ## Introduction to Methods

          body 2
        MD
        entries = [
          entry(level: 1, title: "Introduction"),
          entry(level: 1, title: "Introduction to Methods")
        ]

        result = described_class.call(markdown: md, entries: entries)
        lines = result.map { |r| r[:body_line] }
        expect(lines.compact.uniq.size).to eq(lines.compact.size)
      end
    end

    context "pipe-polluted body heading" do
      it "cleans pipes before matching" do
        md = <<~MD
          ## | 1 | Introduction | 1 |

          Body.
        MD
        entries = [entry(level: 1, number: "1", title: "Introduction")]

        result = described_class.call(markdown: md, entries: entries)
        expect(result.first[:body_line]).to eq(0)
      end
    end
  end
end
