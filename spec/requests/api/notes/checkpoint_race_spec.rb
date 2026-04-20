require "rails_helper"

RSpec.describe "API notes checkpoint/draft race", type: :request do
  let(:user) { create(:user) }

  def build_note(body: "# Body\n")
    note = create(:note, title: "Race")
    rev = create(:note_revision, note: note, revision_kind: :checkpoint, content_markdown: body)
    note.update_columns(head_revision_id: rev.id)
    note
  end

  it "does not let a draft stamped against a stale head shadow the current checkpoint" do
    sign_in user
    note = build_note(body: "checkpoint body")

    # Simulate a draft created while the head was the original revision,
    # but that arrives on the server AFTER a newer checkpoint has replaced it.
    stale_head_id = note.head_revision_id
    new_checkpoint = create(
      :note_revision,
      note: note,
      revision_kind: :checkpoint,
      content_markdown: "new checkpoint content"
    )
    note.update_columns(head_revision_id: new_checkpoint.id)

    create(
      :note_revision,
      note: note,
      revision_kind: :draft,
      content_markdown: "stale draft content",
      base_revision_id: stale_head_id
    )

    get "/api/notes/#{note.slug}"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["revision"]["content_markdown"]).to eq("new checkpoint content")
  end

  it "keeps a fresh draft visible when it was stamped against the current head" do
    sign_in user
    note = build_note(body: "checkpoint body")

    create(
      :note_revision,
      note: note,
      revision_kind: :draft,
      content_markdown: "fresh draft content",
      base_revision_id: note.head_revision_id
    )

    get "/api/notes/#{note.slug}"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["revision"]["content_markdown"]).to eq("fresh draft content")
  end
end
