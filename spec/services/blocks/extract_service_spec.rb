require "rails_helper"

RSpec.describe Blocks::ExtractService do
  describe ".call" do
    it "returns empty array for content with no block markers" do
      expect(described_class.call("# Plain note\n\nNo blocks here.")).to eq([])
    end

    it "returns empty array for nil content" do
      expect(described_class.call(nil)).to eq([])
    end

    it "extracts a paragraph block with ^id at end" do
      content = "This is a paragraph. ^my-block"
      result = described_class.call(content)

      expect(result.size).to eq(1)
      expect(result.first.block_id).to eq("my-block")
      expect(result.first.content).to eq("This is a paragraph.")
      expect(result.first.block_type).to eq("paragraph")
      expect(result.first.position).to eq(0)
    end

    it "extracts a list item block" do
      content = "- Item one ^item1\n- Item two"
      result = described_class.call(content)

      expect(result.size).to eq(1)
      expect(result.first.block_id).to eq("item1")
      expect(result.first.content).to eq("- Item one")
      expect(result.first.block_type).to eq("list_item")
    end

    it "extracts a heading block" do
      content = "## Section Title ^sec-1"
      result = described_class.call(content)

      expect(result.first.block_id).to eq("sec-1")
      expect(result.first.content).to eq("## Section Title")
      expect(result.first.block_type).to eq("heading")
    end

    it "extracts a blockquote block" do
      content = "> Important quote ^quote1"
      result = described_class.call(content)

      expect(result.first.block_id).to eq("quote1")
      expect(result.first.block_type).to eq("blockquote")
    end

    it "ignores ^id inside fenced code blocks" do
      content = "```\nsome code ^not-a-block\n```"
      result = described_class.call(content)

      expect(result).to eq([])
    end

    it "extracts multiple blocks with different types" do
      content = <<~MD
        First paragraph. ^p1

        - A list item ^li1

        ## A heading ^h1
      MD
      result = described_class.call(content)

      expect(result.size).to eq(3)
      expect(result.map(&:block_id)).to eq(%w[p1 li1 h1])
      expect(result.map(&:block_type)).to eq(%w[paragraph list_item heading])
      expect(result.map(&:position)).to eq([0, 1, 2])
    end

    it "requires space before ^ to avoid false positives like 2^10" do
      content = "The result is 2^10 which is 1024."
      result = described_class.call(content)

      expect(result).to eq([])
    end

    it "strips the ^id marker from content" do
      content = "Long paragraph with details. ^ref1"
      result = described_class.call(content)

      expect(result.first.content).not_to include("^ref1")
      expect(result.first.content).to eq("Long paragraph with details.")
    end

    it "truncates long content to 200 characters" do
      long_text = "A" * 250
      content = "#{long_text} ^long1"
      result = described_class.call(content)

      expect(result.first.content.length).to be <= 200
    end

    it "handles trailing whitespace after ^id" do
      content = "Some text ^my-id   "
      result = described_class.call(content)

      expect(result.first.block_id).to eq("my-id")
    end
  end
end
