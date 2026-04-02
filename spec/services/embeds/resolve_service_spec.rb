# frozen_string_literal: true

require "rails_helper"

RSpec.describe Embeds::ResolveService do
  describe ".call" do
    context "heading embeds" do
      let(:content) do
        <<~MD
          # Introduction

          Some intro text.

          ## Details

          Detail paragraph one.

          Detail paragraph two.

          ## Conclusion

          Final thoughts.
        MD
      end

      it "extracts heading section from heading to next same-level heading" do
        result = described_class.call(content: content, heading_slug: "details")

        expect(result.found).to be true
        expect(result.content).to include("## Details")
        expect(result.content).to include("Detail paragraph one.")
        expect(result.content).to include("Detail paragraph two.")
        expect(result.content).not_to include("## Conclusion")
        expect(result.content).not_to include("Final thoughts.")
      end

      it "extracts heading section from heading to next higher-level heading" do
        content_with_levels = <<~MD
          # Top

          ## Sub Section

          Sub content here.

          # Another Top

          More content.
        MD

        result = described_class.call(content: content_with_levels, heading_slug: "sub-section")

        expect(result.found).to be true
        expect(result.content).to include("## Sub Section")
        expect(result.content).to include("Sub content here.")
        expect(result.content).not_to include("# Another Top")
      end

      it "includes sub-headings within the section" do
        content_with_sub = <<~MD
          ## Parent

          Parent text.

          ### Child

          Child text.

          ### Another Child

          More child text.

          ## Sibling

          Sibling text.
        MD

        result = described_class.call(content: content_with_sub, heading_slug: "parent")

        expect(result.found).to be true
        expect(result.content).to include("## Parent")
        expect(result.content).to include("### Child")
        expect(result.content).to include("### Another Child")
        expect(result.content).to include("More child text.")
        expect(result.content).not_to include("## Sibling")
      end

      it "extracts last heading section to end of document" do
        result = described_class.call(content: content, heading_slug: "conclusion")

        expect(result.found).to be true
        expect(result.content).to include("## Conclusion")
        expect(result.content).to include("Final thoughts.")
      end

      it "returns found: false when heading slug does not exist" do
        result = described_class.call(content: content, heading_slug: "nonexistent")

        expect(result.found).to be false
        expect(result.content).to be_nil
      end

      it "ignores headings inside code fences" do
        fenced = <<~MD
          ## Real Heading

          Some text.

          ```
          ## Fake Heading
          ```

          ## Next Heading

          Next text.
        MD

        result = described_class.call(content: fenced, heading_slug: "real-heading")

        expect(result.found).to be true
        expect(result.content).to include("## Real Heading")
        expect(result.content).to include("Some text.")
        expect(result.content).to include("## Fake Heading") # inside fence, part of section
        expect(result.content).not_to include("## Next Heading")
      end

      it "handles duplicate heading slugs by matching first occurrence" do
        duped = <<~MD
          ## Setup

          First setup.

          ## Other

          Middle.

          ## Setup

          Second setup.
        MD

        result = described_class.call(content: duped, heading_slug: "setup")

        expect(result.found).to be true
        expect(result.content).to include("First setup.")
        expect(result.content).not_to include("Middle.")
      end

      it "extracts level-1 heading section up to next level-1 heading" do
        multi_h1 = <<~MD
          # First

          Content one.

          ## Sub

          Sub content.

          # Second

          Content two.
        MD

        result = described_class.call(content: multi_h1, heading_slug: "first")

        expect(result.found).to be true
        expect(result.content).to include("# First")
        expect(result.content).to include("## Sub")
        expect(result.content).not_to include("# Second")
      end
    end

    context "block embeds" do
      let(:content) do
        <<~MD
          # Notes

          This is a key insight. ^key-insight

          - First item
          - Important item ^important

          > A wise quote
          > spanning multiple lines ^wisdom

          ## Code

          ```ruby
          x = 1 ^not-a-block
          ```

          Final paragraph with a very long content that should not be truncated at all because embeds need the full text of the block to display properly in the transclusion preview and we want to make sure there is absolutely no truncation happening here at all. ^long-block
        MD
      end

      it "extracts block content for paragraph with ^block-id" do
        result = described_class.call(content: content, block_id: "key-insight")

        expect(result.found).to be true
        expect(result.content).to eq("This is a key insight.")
      end

      it "extracts block content for list item" do
        result = described_class.call(content: content, block_id: "important")

        expect(result.found).to be true
        expect(result.content).to eq("- Important item")
      end

      it "extracts blockquote with contiguous > lines" do
        result = described_class.call(content: content, block_id: "wisdom")

        expect(result.found).to be true
        expect(result.content).to include("A wise quote")
        expect(result.content).to include("spanning multiple lines")
      end

      it "strips the ^block-id marker from returned content" do
        result = described_class.call(content: content, block_id: "key-insight")

        expect(result.content).not_to include("^key-insight")
      end

      it "returns full content without truncation" do
        result = described_class.call(content: content, block_id: "long-block")

        expect(result.found).to be true
        expect(result.content.length).to be > 200
        expect(result.content).not_to include("...")
      end

      it "returns found: false when block_id does not exist" do
        result = described_class.call(content: content, block_id: "nonexistent")

        expect(result.found).to be false
      end

      it "ignores blocks inside code fences" do
        result = described_class.call(content: content, block_id: "not-a-block")

        expect(result.found).to be false
      end
    end

    context "edge cases" do
      it "returns found: false for nil content" do
        result = described_class.call(content: nil, heading_slug: "anything")

        expect(result.found).to be false
      end

      it "returns found: false when neither heading nor block given" do
        result = described_class.call(content: "# Hello\n\nWorld")

        expect(result.found).to be false
      end
    end
  end
end
