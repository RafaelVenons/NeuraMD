require "rails_helper"

RSpec.describe Links::ExtractService do
  describe ".call" do
    it "returns empty array for content with no wiki-links" do
      expect(described_class.call("# Plain note\n\nNo links here.")).to eq([])
    end

    it "extracts a simple wiki-link with no role" do
      uuid = SecureRandom.uuid
      result = described_class.call("See [[Note A|#{uuid}]] for details.")
      expect(result).to eq([{dst_note_id: uuid, hier_role: nil}])
    end

    it "extracts father role (f:)" do
      uuid = SecureRandom.uuid
      result = described_class.call("[[Parent Note|f:#{uuid}]]")
      expect(result).to eq([{dst_note_id: uuid, hier_role: "target_is_parent"}])
    end

    it "extracts child role (c:)" do
      uuid = SecureRandom.uuid
      result = described_class.call("[[Child Note|c:#{uuid}]]")
      expect(result).to eq([{dst_note_id: uuid, hier_role: "target_is_child"}])
    end

    it "extracts brother role (b:)" do
      uuid = SecureRandom.uuid
      result = described_class.call("[[Sibling|b:#{uuid}]]")
      expect(result).to eq([{dst_note_id: uuid, hier_role: "same_level"}])
    end

    it "extracts next role (n:)" do
      uuid = SecureRandom.uuid
      result = described_class.call("[[Next Chapter|n:#{uuid}]]")
      expect(result).to eq([{dst_note_id: uuid, hier_role: "next_in_sequence"}])
    end

    it "treats unknown roles as plain links while preserving the destination" do
      uuid = SecureRandom.uuid
      result = described_class.call("[[Sibling|x:#{uuid}]]")
      expect(result).to eq([{dst_note_id: uuid, hier_role: nil}])
    end

    it "deduplicates same UUID with same role" do
      uuid = SecureRandom.uuid
      content = "[[Note|#{uuid}]] and again [[Note|#{uuid}]]"
      result = described_class.call(content)
      expect(result.size).to eq(1)
    end

    it "prefers the explicit role when the same UUID appears multiple times" do
      uuid = SecureRandom.uuid
      content = "[[Note|#{uuid}]] and [[Parent|f:#{uuid}]] and [[Sibling|b:#{uuid}]]"
      result = described_class.call(content)
      expect(result).to eq([{dst_note_id: uuid, hier_role: "same_level"}])
    end

    it "prefers a meaningful semantic role over unknown roles for the same UUID" do
      uuid = SecureRandom.uuid
      content = "[[Note|x:#{uuid}]] and [[Parent|f:#{uuid}]]"
      result = described_class.call(content)
      expect(result).to eq([{dst_note_id: uuid, hier_role: "target_is_parent"}])
    end

    it "extracts multiple different wiki-links" do
      uuid1 = SecureRandom.uuid
      uuid2 = SecureRandom.uuid
      uuid3 = SecureRandom.uuid
      content = "[[Note A|#{uuid1}]] and [[Note B|c:#{uuid2}]] and [[Note C|x:#{uuid3}]]"
      result = described_class.call(content)
      expect(result).to contain_exactly(
        {dst_note_id: uuid1, hier_role: nil},
        {dst_note_id: uuid2, hier_role: "target_is_child"},
        {dst_note_id: uuid3, hier_role: nil}
      )
    end

    it "normalises UUIDs to downcase" do
      uuid = SecureRandom.uuid.upcase
      result = described_class.call("[[Note|#{uuid}]]")
      expect(result.first[:dst_note_id]).to eq(uuid.downcase)
    end

    it "ignores malformed markup without UUID" do
      result = described_class.call("[[Not a link]] and [[Also not|not-uuid]]")
      expect(result).to eq([])
    end

    # ── EPIC-03.2: heading fragment support ──────────────────

    it "extracts heading_slug from [[Display|uuid#heading-slug]]" do
      uuid = SecureRandom.uuid
      result = described_class.call("See [[Note A|#{uuid}#introduction]] for details.")
      expect(result).to eq([{dst_note_id: uuid, hier_role: nil, heading_slugs: ["introduction"]}])
    end

    it "extracts heading_slug with role [[Display|f:uuid#slug]]" do
      uuid = SecureRandom.uuid
      result = described_class.call("[[Parent|f:#{uuid}#overview]]")
      expect(result).to eq([{dst_note_id: uuid, hier_role: "target_is_parent", heading_slugs: ["overview"]}])
    end

    it "returns nil heading_slugs when no fragment" do
      uuid = SecureRandom.uuid
      result = described_class.call("[[Note|#{uuid}]]")
      expect(result.first[:heading_slugs]).to be_nil
    end

    it "collects multiple heading_slugs for same UUID" do
      uuid = SecureRandom.uuid
      content = "[[Note|#{uuid}#intro]] and [[Note|#{uuid}#methods]]"
      result = described_class.call(content)
      expect(result.size).to eq(1)
      expect(result.first[:heading_slugs]).to contain_exactly("intro", "methods")
    end

    it "collects heading_slugs and preserves role priority" do
      uuid = SecureRandom.uuid
      content = "[[Note|#{uuid}#intro]] and [[Note|f:#{uuid}#methods]]"
      result = described_class.call(content)
      expect(result.first[:hier_role]).to eq("target_is_parent")
      expect(result.first[:heading_slugs]).to contain_exactly("intro", "methods")
    end

    it "mixes links with and without heading fragments" do
      uuid1 = SecureRandom.uuid
      uuid2 = SecureRandom.uuid
      content = "[[Note A|#{uuid1}#section]] and [[Note B|#{uuid2}]]"
      result = described_class.call(content)
      a = result.find { |l| l[:dst_note_id] == uuid1 }
      b = result.find { |l| l[:dst_note_id] == uuid2 }
      expect(a[:heading_slugs]).to eq(["section"])
      expect(b[:heading_slugs]).to be_nil
    end

    # ── EPIC-03.3: block reference support ───────────────────

    it "extracts block_id from [[Display|uuid^block-id]]" do
      uuid = SecureRandom.uuid
      result = described_class.call("See [[Note|#{uuid}^my-block]] here.")
      expect(result).to eq([{dst_note_id: uuid, hier_role: nil, block_ids: ["my-block"]}])
    end

    it "extracts block_id with role" do
      uuid = SecureRandom.uuid
      result = described_class.call("[[Parent|f:#{uuid}^ref1]]")
      expect(result).to eq([{dst_note_id: uuid, hier_role: "target_is_parent", block_ids: ["ref1"]}])
    end

    it "collects multiple block_ids for same UUID" do
      uuid = SecureRandom.uuid
      content = "[[Note|#{uuid}^b1]] and [[Note|#{uuid}^b2]]"
      result = described_class.call(content)
      expect(result.size).to eq(1)
      expect(result.first[:block_ids]).to contain_exactly("b1", "b2")
    end

    # ── EPIC-03.4: embeds should not produce links ────────

    it "does not extract embed references (![[...]])" do
      uuid = SecureRandom.uuid
      content = "![[Embedded Note|#{uuid}#intro]]"
      result = described_class.call(content)
      expect(result).to eq([])
    end

    it "extracts normal wikilink but skips embed on same line" do
      uuid1 = SecureRandom.uuid
      uuid2 = SecureRandom.uuid
      content = "![[Embed|#{uuid1}]] and [[Link|#{uuid2}]]"
      result = described_class.call(content)
      expect(result.size).to eq(1)
      expect(result.first[:dst_note_id]).to eq(uuid2)
    end

    it "keeps heading and block separate for different links" do
      uuid1 = SecureRandom.uuid
      uuid2 = SecureRandom.uuid
      content = "[[A|#{uuid1}#intro]] and [[B|#{uuid2}^ref1]]"
      result = described_class.call(content)
      a = result.find { |l| l[:dst_note_id] == uuid1 }
      b = result.find { |l| l[:dst_note_id] == uuid2 }
      expect(a[:heading_slugs]).to eq(["intro"])
      expect(a[:block_ids]).to be_nil
      expect(b[:block_ids]).to eq(["ref1"])
      expect(b[:heading_slugs]).to be_nil
    end
  end
end
