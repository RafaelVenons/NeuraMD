require "rails_helper"

# Validates the JS wikilink_controller._detectCursorInLink logic in Ruby.
#
# The JS pattern:
#   FULL_RE = /\[\[([^\]|]+)\|([a-z]+:)?([uuid])\]\]/gi
#
# Boundary condition (fixed): cursorPos >= from && cursorPos <= to
#   — previously strict (> and <), which missed position 0 and end-of-text.
#
# Key regression: a note whose entire content is [[Title|uuid]] must enter
# link mode for ALL cursor positions (0 through text.length inclusive).
#
RSpec.describe "JS wikilink cursor detection (boundary logic mirror)" do
  # Ruby mirror of the JS FULL_RE pattern
  UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i
  FULL_RE = /\[\[([^\]|]+)\|([a-z]+:)?(#{UUID_RE})\]\]/i

  # Returns the wiki-link that the cursor at `cursor_pos` is inside, or nil.
  def detect_link(content, cursor_pos)
    content.scan(FULL_RE).each do |display, role_prefix, uuid|
      match  = FULL_RE.match(content)
      from   = match.begin(0)
      to     = match.end(0)
      return {display: display, role: role_prefix&.delete(":"), uuid: uuid, from: from, to: to} \
        if cursor_pos >= from && cursor_pos <= to
    end
    nil
  end

  # Multi-match version (handles notes with multiple links)
  def detect_link_multi(content, cursor_pos)
    pos = 0
    content.scan(FULL_RE) do |display, role_prefix, uuid|
      match = Regexp.last_match
      from  = match.begin(0)
      to    = match.end(0)
      return {display: display, role: role_prefix&.delete(":"), uuid: uuid, from: from, to: to} \
        if cursor_pos >= from && cursor_pos <= to
    end
    nil
  end

  let(:uuid) { "550e8400-e29b-41d4-a716-446655440000" }

  describe "note whose ENTIRE content is one wiki-link" do
    let(:content) { "[[Título da Nota|#{uuid}]]" }

    it "detects the link for every cursor position 0..length" do
      (0..content.length).each do |pos|
        result = detect_link_multi(content, pos)
        expect(result).not_to be_nil,
          "Expected link mode at cursor position #{pos} (content length #{content.length}), got nil"
        expect(result[:uuid]).to eq(uuid)
      end
    end

    it "detects link at position 0 (was broken with strict > from)" do
      expect(detect_link_multi(content, 0)).not_to be_nil
    end

    it "detects link at final position = content.length (was broken with strict < to)" do
      expect(detect_link_multi(content, content.length)).not_to be_nil
    end
  end

  describe "note with text before and after the link" do
    let(:content) { "Texto antes. [[Nota|#{uuid}]] Texto depois." }

    it "returns nil when cursor is in text before the link" do
      # cursor at position 0 (before the link)
      expect(detect_link_multi(content, 0)).to be_nil
    end

    it "detects link when cursor is at the opening [[ boundary" do
      from = content.index("[[")
      expect(detect_link_multi(content, from)).not_to be_nil
    end

    it "detects link when cursor is at the closing ]] boundary" do
      to = content.index("]]") + 2
      expect(detect_link_multi(content, to)).not_to be_nil
    end

    it "returns nil when cursor is in text after the link" do
      after_link = content.index("]]") + 3
      expect(detect_link_multi(content, after_link)).to be_nil
    end
  end

  describe "link with hier_role prefix" do
    it "detects father role f:" do
      text = "[[Parent|f:#{uuid}]]"
      result = detect_link_multi(text, 5)
      expect(result[:role]).to eq("f")
    end

    it "detects child role c:" do
      text = "[[Child|c:#{uuid}]]"
      result = detect_link_multi(text, 5)
      expect(result[:role]).to eq("c")
    end

    it "detects brother role b:" do
      text = "[[Sibling|b:#{uuid}]]"
      result = detect_link_multi(text, 5)
      expect(result[:role]).to eq("b")
    end

    it "role is nil for plain reference" do
      text = "[[Plain|#{uuid}]]"
      result = detect_link_multi(text, 5)
      expect(result[:role]).to be_nil
    end

    it "detects arbitrary role prefixes without treating them as broken syntax" do
      text = "[[Custom|x:#{uuid}]]"
      result = detect_link_multi(text, 5)
      expect(result[:role]).to eq("x")
    end
  end
end
