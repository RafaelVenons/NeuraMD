require "rails_helper"

RSpec.describe Notes::PromiseCleanupService do
  let(:source_note) { create(:note, :with_head_revision) }
  let(:target_note) { create(:note, title: "Promessa IA") }
  let(:request_record) do
    create(
      :ai_request,
      note_revision: source_note.head_revision,
      capability: "seed_note",
      status: "queued",
      metadata: {
        "language" => source_note.detected_language,
        "promise_source_note_id" => source_note.id,
        "promise_note_id" => target_note.id,
        "promise_note_title" => target_note.title
      }
    )
  end

  it "cancels the request and soft-deletes the promise note" do
    Notes::DraftService.call(note: source_note, content: "Abrir [[Promessa IA|#{target_note.id}]]", author: nil)

    result = described_class.call(ai_request: request_record)

    expect(result.request_canceled).to be(true)
    expect(result.note_deleted).to be(true)
    expect(result.graph_changed).to be(true)
    expect(result.source_content).to eq("Abrir [[Promessa IA]]")
    expect(request_record.reload.status).to eq("canceled")
    expect(target_note.reload).to be_deleted
    expect(source_note.reload.note_revisions.find_by(revision_kind: :draft).content_markdown).to eq("Abrir [[Promessa IA]]")
    expect(request_record.metadata["promise_cleanup_at"]).to be_present
  end
end
