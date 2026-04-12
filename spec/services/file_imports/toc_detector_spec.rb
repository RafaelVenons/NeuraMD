# frozen_string_literal: true

require "rails_helper"

RSpec.describe FileImports::TocDetector do
  describe ".call" do
    context "with no anchor" do
      it "returns nil" do
        md = "# Some Book\n\nIntro text.\n\n## Chapter 1\n\nBody.\n"
        expect(described_class.call(markdown: md)).to be_nil
      end
    end

    context "with fewer than 3 parseable entries" do
      it "returns nil" do
        md = <<~MD
          # Book

          ## Contents

          1 Introduction
        MD
        expect(described_class.call(markdown: md)).to be_nil
      end
    end

    context "with a simple heading anchor" do
      it "detects Contents and numbered chapters" do
        md = <<~MD
          # Book

          ## Contents

          1 Introduction    1
          2 Methods         15
          3 Results         40
          4 Discussion      60

          ## 1 Introduction

          Body.
        MD

        result = described_class.call(markdown: md)
        expect(result).not_to be_nil
        expect(result[:anchor_kind]).to eq("Contents")
        first_four = result[:entries].first(4)
        expect(first_four.map(&:title)).to eq(
          ["Introduction", "Methods", "Results", "Discussion"]
        )
        expect(first_four.map(&:page)).to eq([1, 15, 40, 60])
      end
    end

    context "with bold-wrapped anchor (Norvig-style)" do
      it "detects ## **Sumário**" do
        md = <<~MD
          # Livro

          ## **Sumário**

          1 Introdução
          2 Métodos
          3 Resultados
        MD

        result = described_class.call(markdown: md)
        expect(result).not_to be_nil
        expect(result[:anchor_kind].strip).to match(/Sum[áa]rio/)
        expect(result[:entries].size).to be >= 3
      end
    end

    context "with bold-only anchor" do
      it "detects **Sumário** alone on a line" do
        md = <<~MD
          Prefácio.

          **Sumário**

          1 Introdução
          2 Métodos
          3 Resultados
        MD

        result = described_class.call(markdown: md)
        expect(result).not_to be_nil
        expect(result[:entries].size).to be >= 3
      end
    end

    context "with PARTE/CHAPTER structured prefixes (Luger-style)" do
      it "captures parts at level 0 and chapters at level 1" do
        md = <<~MD
          ## CONTENTS

          PART I ARTIFICIAL INTELLIGENCE: ITS ROOTS AND SCOPE
          CHAPTER 1 AI: History and Applications
          CHAPTER 2 The Predicate Calculus
          PART II ARTIFICIAL INTELLIGENCE AS REPRESENTATION AND SEARCH
          CHAPTER 3 Structures and Strategies for State Space Search
        MD

        result = described_class.call(markdown: md)
        expect(result).not_to be_nil
        parts = result[:entries].select { |e| e.level == 0 }
        chapters = result[:entries].select { |e| e.number.to_s.match?(/\A\d+\z/) }
        expect(parts.size).to eq(2)
        expect(chapters.size).to be >= 3
      end
    end

    context "with blocklisted boilerplate titles" do
      it "drops Preface/Cover/Index entries" do
        md = <<~MD
          ## Contents

          Preface
          Cover
          Title Page
          1 Introduction
          2 Methods
          3 Results
          Index
          Bibliography
        MD

        result = described_class.call(markdown: md)
        expect(result).not_to be_nil
        titles = result[:entries].map(&:title).map(&:downcase)
        expect(titles).not_to include("preface")
        expect(titles).not_to include("cover")
        expect(titles).not_to include("index")
        expect(titles.any? { |t| t.include?("introduction") }).to be true
      end
    end

    context "with N.N.N numeric prefix" do
      it "infers depth from number" do
        md = <<~MD
          ## Contents

          1 Introduction
          1.1 Background
          1.2 Motivation
          2 Methods
        MD

        result = described_class.call(markdown: md)
        expect(result).not_to be_nil
        by_num = result[:entries].index_by(&:number)
        expect(by_num["1"].level).to eq(1)
        expect(by_num["1.1"].level).to eq(2)
        expect(by_num["1.2"].level).to eq(2)
        expect(by_num["2"].level).to eq(1)
      end
    end

    context "with pipe-column polluted lines (Witten-style)" do
      it "cleans pipes and extracts title" do
        md = <<~MD
          ## Contents

          | 1 | What's it all about? | 1 |
          | 2 | Input: concepts, instances, attributes | 40 |
          | 3 | Output: knowledge representation | 60 |
        MD

        result = described_class.call(markdown: md)
        expect(result).not_to be_nil
        titles = result[:entries].map(&:title)
        expect(titles).to include(match(/What.?s it all about/))
        expect(titles.none? { |t| t.include?("|") }).to be true
      end
    end

    context "prefers 'Contents' over 'Brief Contents' when both present" do
      it "picks the detailed TOC" do
        md = <<~MD
          ## Brief Contents

          Part I
          Part II
          Part III

          ## Contents

          1 Introduction
          2 Methods
          3 Results
          4 Discussion
        MD

        result = described_class.call(markdown: md)
        expect(result).not_to be_nil
        expect(result[:anchor_kind].downcase).to eq("contents")
      end
    end

    context "when body headings use the same format as TOC entries" do
      it "over-captures rather than risk truncating real TOCs (HeadingMatcher disambiguates downstream)" do
        md = <<~MD
          ## Contents

          1 Introduction
          2 Methods
          3 Results

          ## 1 Introduction

          Body of introduction here.

          ## 2 Methods

          Body of methods.
        MD

        result = described_class.call(markdown: md)
        expect(result).not_to be_nil
        expect(result[:entries].size).to be >= 3
      end
    end
  end
end
