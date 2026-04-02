require "rails_helper"

RSpec.describe Headings::ExtractService do
  def extract(content)
    described_class.call(content)
  end

  it "extracts a single heading with level, text, slug, and position" do
    result = extract("# Introduction")

    expect(result.size).to eq(1)
    h = result.first
    expect(h.level).to eq(1)
    expect(h.text).to eq("Introduction")
    expect(h.slug).to eq("introduction")
    expect(h.position).to eq(0)
  end

  it "extracts multiple headings at different levels" do
    content = <<~MD
      # Title
      Some text.
      ## Section A
      More text.
      ### Subsection
    MD

    result = extract(content)

    expect(result.map(&:level)).to eq([1, 2, 3])
    expect(result.map(&:text)).to eq(["Title", "Section A", "Subsection"])
    expect(result.map(&:position)).to eq([0, 1, 2])
  end

  it "generates transliterated slugs for accented text" do
    result = extract("## Seção de Introdução")

    expect(result.first.slug).to eq("secao-de-introducao")
  end

  it "deduplicates slugs with numeric suffixes" do
    content = <<~MD
      ## Seção
      Text.
      ## Seção
      More text.
      ## Seção
    MD

    slugs = extract(content).map(&:slug)
    expect(slugs).to eq(["secao", "secao-1", "secao-2"])
  end

  it "ignores headings inside fenced code blocks" do
    content = <<~MD
      ## Real Heading
      ```
      ## Not A Heading
      ```
      ## Another Real Heading
    MD

    result = extract(content)

    expect(result.map(&:text)).to eq(["Real Heading", "Another Real Heading"])
  end

  it "strips inline markdown from heading text" do
    content = <<~MD
      ## **Bold** and _italic_
      ## `code` heading
      ## [Link Text](http://example.com)
    MD

    texts = extract(content).map(&:text)
    expect(texts).to eq(["Bold and italic", "code heading", "Link Text"])
  end

  it "returns empty array for content with no headings" do
    result = extract("Just some plain text.\nNo headings here.")

    expect(result).to eq([])
  end

  it "returns empty array for nil content" do
    expect(extract(nil)).to eq([])
  end

  it "handles headings up to level 6" do
    content = "###### Deep Heading"
    result = extract(content)

    expect(result.first.level).to eq(6)
    expect(result.first.text).to eq("Deep Heading")
  end

  it "ignores lines with more than 6 hashes" do
    result = extract("####### Not a heading")

    expect(result).to eq([])
  end

  it "requires a space after the hash marks" do
    result = extract("##NoSpace")

    expect(result).to eq([])
  end
end
