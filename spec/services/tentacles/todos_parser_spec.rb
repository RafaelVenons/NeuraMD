require "rails_helper"

RSpec.describe Tentacles::TodosParser do
  describe ".parse" do
    it "returns an empty array when no Todos section is present" do
      expect(described_class.parse("some text\n")).to eq([])
    end

    it "parses checked and unchecked items in order" do
      body = <<~MD
        Intro text.

        ## Todos

        - [ ] first
        - [x] second done
        - [X] third upper

        ## Other section

        - [ ] not a todo
      MD

      expect(described_class.parse(body)).to eq([
        { text: "first", done: false },
        { text: "second done", done: true },
        { text: "third upper", done: true }
      ])
    end

    it "stops at the next same-or-higher heading" do
      body = <<~MD
        ## Todos

        - [ ] a
        ### subsection
        - [ ] b
        ## Notes
        - [ ] c
      MD

      expect(described_class.parse(body)).to eq([
        { text: "a", done: false },
        { text: "b", done: false }
      ])
    end

    it "is case-insensitive for the heading" do
      body = "## TODOS\n\n- [ ] yo\n"
      expect(described_class.parse(body)).to eq([{ text: "yo", done: false }])
    end
  end

  describe ".replace" do
    it "appends a Todos section when none exists" do
      body = "Existing body.\n"
      result = described_class.replace(body, [{ text: "a", done: false }, { text: "b", done: true }])

      expect(result).to include("Existing body.")
      expect(result).to match(/\n## Todos\n\n- \[ \] a\n- \[x\] b\n/)
    end

    it "replaces an existing Todos section without touching surrounding content" do
      body = <<~MD
        Intro

        ## Todos

        - [ ] old one
        - [x] old two

        ## After

        Content after.
      MD

      result = described_class.replace(body, [{ text: "new", done: true }])
      expect(result).to include("Intro")
      expect(result).to include("## After")
      expect(result).to include("Content after.")
      expect(result).to include("- [x] new")
      expect(result).not_to include("old one")
      expect(result).not_to include("old two")
    end

    it "emits an empty Todos section when todos is []" do
      body = "## Todos\n\n- [ ] foo\n"
      result = described_class.replace(body, [])
      expect(described_class.parse(result)).to eq([])
      expect(result).to include("## Todos")
    end

    it "is round-trippable" do
      todos = [
        { text: "one", done: false },
        { text: "two with spaces", done: true },
        { text: "three", done: false }
      ]
      result = described_class.replace("lead\n", todos)
      expect(described_class.parse(result)).to eq(todos)
    end
  end
end
