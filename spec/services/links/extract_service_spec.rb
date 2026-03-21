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
  end
end
