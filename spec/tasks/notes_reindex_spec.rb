require "rails_helper"
require "rake"

RSpec.describe "notes:reindex", type: :task do
  before(:all) do
    Rails.application.load_tasks
  end

  let(:user) { create(:user) }

  it "re-syncs links for all active notes with head revisions" do
    target = create(:note, title: "Target")
    create(:note_revision, note: target, revision_kind: :checkpoint, content_markdown: "Target content")

    source = create(:note, title: "Source")
    revision = create(:note_revision, note: source, revision_kind: :checkpoint,
      content_markdown: "Link to [[Target|#{target.id}]]", author: user)
    source.update_columns(head_revision_id: revision.id)

    # Manually remove the link to simulate stale state
    NoteLink.where(src_note_id: source.id).delete_all

    expect(NoteLink.where(src_note_id: source.id, dst_note_id: target.id).count).to eq(0)

    Rake::Task["notes:reindex"].reenable
    Rake::Task["notes:reindex"].invoke

    link = NoteLink.find_by(src_note_id: source.id, dst_note_id: target.id)
    expect(link).to be_present
    expect(link.active).to be true
  end

  it "skips deleted notes" do
    deleted_note = create(:note, :deleted, title: "Deleted")
    revision = create(:note_revision, note: deleted_note, revision_kind: :checkpoint,
      content_markdown: "some content")
    deleted_note.update_columns(head_revision_id: revision.id)

    Rake::Task["notes:reindex"].reenable
    expect { Rake::Task["notes:reindex"].invoke }.not_to raise_error
  end

  it "skips notes without head revision" do
    create(:note, title: "No Head")

    Rake::Task["notes:reindex"].reenable
    expect { Rake::Task["notes:reindex"].invoke }.not_to raise_error
  end
end
