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
      expect(link.active).to be(true)
    end

    it "creates link with correct hier_role" do
      content = "[[Dest|f:#{dst_note.id}]]"
      call(content)
      expect(src_note.outgoing_links.last.hier_role).to eq("target_is_parent")
    end

    it "treats unknown roles as plain links instead of rejecting them" do
      content = "[[Dest|x:#{dst_note.id}]]"

      expect { call(content) }.to change(NoteLink, :count).by(1)
      expect(src_note.outgoing_links.last.hier_role).to be_nil
    end

    it "deletes links removed from content" do
      call("[[Dest|#{dst_note.id}]]")
      expect { call("No links anymore.") }.not_to change(NoteLink, :count)
      expect(src_note.outgoing_links.find_by(dst_note_id: dst_note.id)).not_to be_active
    end

    it "does not create duplicate links for the same dst+role" do
      content = "[[Dest|#{dst_note.id}]] and again [[Dest|#{dst_note.id}]]"
      expect { call(content) }.to change(NoteLink, :count).by(1)
    end

    it "updates the existing link role instead of creating a duplicate when the role changes" do
      call("[[Dest|#{dst_note.id}]]")

      expect {
        call("[[Dest|b:#{dst_note.id}]]")
      }.not_to change(NoteLink, :count)

      expect(src_note.outgoing_links.find_by(dst_note_id: dst_note.id).hier_role).to eq("same_level")
    end

    it "upgrades an unknown role to a semantic one when the latest content adds meaning" do
      call("[[Dest|x:#{dst_note.id}]]")

      expect {
        call("[[Dest|c:#{dst_note.id}]]")
      }.not_to change(NoteLink, :count)

      expect(src_note.outgoing_links.find_by(dst_note_id: dst_note.id).hier_role).to eq("target_is_child")
    end

    it "collapses repeated references to the same dst into one link" do
      content = "[[Dest|#{dst_note.id}]] and [[Dest|b:#{dst_note.id}]]"

      expect { call(content) }.to change(NoteLink, :count).by(1)
      expect(src_note.outgoing_links.find_by(dst_note_id: dst_note.id).hier_role).to eq("same_level")
    end

    it "is idempotent — calling twice does not create duplicates" do
      content = "[[Dest|#{dst_note.id}]]"
      call(content)
      expect { call(content) }.not_to change(NoteLink, :count)
    end

    it "reactivates an inactive link when it returns to the latest content" do
      call("[[Dest|#{dst_note.id}]]")
      call("Sem links")

      expect(src_note.outgoing_links.find_by(dst_note_id: dst_note.id)).not_to be_active

      expect { call("[[Dest|#{dst_note.id}]]") }.not_to change(NoteLink, :count)
      expect(src_note.outgoing_links.find_by(dst_note_id: dst_note.id)).to be_active
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

    it "does not create links for unresolved promise wikilinks" do
      expect { call("[[Nota futura]]") }.not_to change(NoteLink, :count)
    end
  end
end
