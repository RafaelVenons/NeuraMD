require "rails_helper"

RSpec.describe Links::SyncService do
  let(:src_note)  { create(:note) }
  let(:dst_note)  { create(:note) }
  let(:revision)  { create(:note_revision, note: src_note) }

  def call(content)
    described_class.call(src_note: src_note, revision: revision, content: content)
  end

  describe ".call" do
    it "creates a link when a wiki-link is present in content" do
      content = "[[Dest|#{dst_note.id}]]"
      expect { call(content) }.to change(NoteLink, :count).by(1)

      link = src_note.outgoing_links.last
      expect(link.dst_note_id).to eq(dst_note.id)
      expect(link.hier_role).to be_nil
    end

    it "creates link with correct hier_role" do
      content = "[[Dest|f:#{dst_note.id}]]"
      call(content)
      expect(src_note.outgoing_links.last.hier_role).to eq("target_is_parent")
    end

    it "deletes links removed from content" do
      call("[[Dest|#{dst_note.id}]]")
      expect { call("No links anymore.") }.to change(NoteLink, :count).by(-1)
    end

    it "does not create duplicate links for the same dst+role" do
      content = "[[Dest|#{dst_note.id}]] and again [[Dest|#{dst_note.id}]]"
      expect { call(content) }.to change(NoteLink, :count).by(1)
    end

    it "is idempotent — calling twice does not create duplicates" do
      content = "[[Dest|#{dst_note.id}]]"
      call(content)
      expect { call(content) }.not_to change(NoteLink, :count)
    end

    it "ignores self-links" do
      content = "[[Self|#{src_note.id}]]"
      expect { call(content) }.not_to change(NoteLink, :count)
    end

    it "ignores links to non-existent notes (broken links)" do
      content = "[[Broken|#{SecureRandom.uuid}]]"
      expect { call(content) }.not_to change(NoteLink, :count)
    end

    it "ignores links to soft-deleted notes" do
      dst_note.soft_delete!
      content = "[[Deleted|#{dst_note.id}]]"
      expect { call(content) }.not_to change(NoteLink, :count)
    end
  end
end
