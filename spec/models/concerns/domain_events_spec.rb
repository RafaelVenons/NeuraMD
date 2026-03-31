require "rails_helper"

RSpec.describe "Domain Events (EPIC-00.3)", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  def capture_events(pattern)
    events = []
    callback = ->(_name, _start, _finish, _id, payload) { events << [_name, payload] }
    ActiveSupport::Notifications.subscribed(callback, pattern) do
      yield
    end
    events
  end

  describe "note.created" do
    it "is emitted when a note is created via controller" do
      events = capture_events("neuramd.note.created") do
        post notes_path, params: {note: {title: "Evento Test", note_kind: "markdown"}}
      end

      expect(events.size).to eq(1)
      expect(events.first[1]).to include(title: "Evento Test")
    end

    it "is emitted by PromiseCreationService" do
      source = create(:note, :with_head_revision, title: "Source")

      events = capture_events("neuramd.note.created") do
        Notes::PromiseCreationService.call(source_note: source, title: "Promise Note", author: user, mode: "blank")
      end

      expect(events.size).to eq(1)
      expect(events.first[1]).to include(title: "Promise Note")
    end
  end

  describe "note.updated" do
    it "is emitted by CheckpointService" do
      note = create(:note, title: "Update Test")

      events = capture_events("neuramd.note.updated") do
        Notes::CheckpointService.call(note: note, content: "content", author: user)
      end

      expect(events.size).to eq(1)
      payload = events.first[1]
      expect(payload[:note_id]).to eq(note.id)
      expect(payload[:revision_id]).to be_present
    end
  end

  describe "note.renamed" do
    it "is emitted by RenameService" do
      note = create(:note, title: "Antes")

      events = capture_events("neuramd.note.renamed") do
        Notes::RenameService.call(note: note, new_title: "Depois")
      end

      expect(events.size).to eq(1)
      payload = events.first[1]
      expect(payload[:old_title]).to eq("Antes")
      expect(payload[:new_title]).to eq("Depois")
      expect(payload[:old_slug]).to eq("antes")
      expect(payload[:new_slug]).to eq("depois")
    end

    it "is not emitted when title is unchanged" do
      note = create(:note, title: "Igual")

      events = capture_events("neuramd.note.renamed") do
        Notes::RenameService.call(note: note, new_title: "Igual")
      end

      expect(events).to be_empty
    end
  end

  describe "note.deleted" do
    it "is emitted by soft_delete!" do
      note = create(:note, title: "Deletar")

      events = capture_events("neuramd.note.deleted") do
        note.soft_delete!
      end

      expect(events.size).to eq(1)
      expect(events.first[1]).to include(note_id: note.id, slug: note.slug)
    end
  end

  describe "note.restored" do
    it "is emitted by restore!" do
      note = create(:note, :deleted, title: "Restaurar")

      events = capture_events("neuramd.note.restored") do
        note.restore!
      end

      expect(events.size).to eq(1)
      expect(events.first[1]).to include(note_id: note.id, slug: note.slug)
    end
  end

  describe "link.created" do
    it "is emitted when SyncService creates a new link" do
      source = create(:note, title: "Link Source")
      target = create(:note, title: "Link Target")

      events = capture_events("neuramd.link.created") do
        Notes::CheckpointService.call(
          note: source,
          content: "ref [[Link Target|#{target.id}]]",
          author: user
        )
      end

      expect(events.size).to eq(1)
      payload = events.first[1]
      expect(payload[:src_note_id]).to eq(source.id)
      expect(payload[:dst_note_id]).to eq(target.id.to_s)
    end

    it "is emitted when SyncService reactivates an inactive link" do
      source = create(:note, title: "Reactivate Source")
      target = create(:note, title: "Reactivate Target")
      Notes::CheckpointService.call(note: source, content: "ref [[RT|#{target.id}]]", author: user)

      # Deactivate the link
      Notes::CheckpointService.call(note: source, content: "no links", author: user)
      expect(NoteLink.find_by(src_note_id: source.id, dst_note_id: target.id).active).to be false

      # Reactivate
      events = capture_events("neuramd.link.created") do
        Notes::CheckpointService.call(note: source, content: "ref [[RT|#{target.id}]]", author: user)
      end

      expect(events.size).to eq(1)
    end
  end

  describe "link.deleted" do
    it "is emitted when SyncService deactivates links" do
      source = create(:note, title: "Unlink Source")
      target = create(:note, title: "Unlink Target")
      Notes::CheckpointService.call(note: source, content: "ref [[UT|#{target.id}]]", author: user)

      events = capture_events("neuramd.link.deleted") do
        Notes::CheckpointService.call(note: source, content: "no more links", author: user)
      end

      expect(events.size).to eq(1)
      payload = events.first[1]
      expect(payload[:src_note_id]).to eq(source.id)
      expect(payload[:dst_note_ids]).to include(target.id)
    end
  end

  describe "property.changed" do
    it "is emitted when a tag is attached to a note" do
      note = create(:note, title: "Tag Test")
      tag = create(:tag, name: "test-tag", tag_scope: "note")

      events = capture_events("neuramd.property.changed") do
        post note_tags_path, params: {note_id: note.id, tag_id: tag.id}
      end

      expect(events.size).to eq(1)
      payload = events.first[1]
      expect(payload).to include(note_id: note.id, property: "tags", action: "attached", value: "test-tag")
    end

    it "is emitted when a tag is detached from a note" do
      note = create(:note, title: "Detach Test")
      tag = create(:tag, name: "detach-tag", tag_scope: "note")
      NoteTag.create!(note: note, tag: tag)

      events = capture_events("neuramd.property.changed") do
        delete note_tags_path, params: {note_id: note.id, tag_id: tag.id}
      end

      expect(events.size).to eq(1)
      payload = events.first[1]
      expect(payload).to include(property: "tags", action: "detached", value: "detach-tag")
    end
  end
end
