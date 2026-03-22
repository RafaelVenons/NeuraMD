require "rails_helper"

RSpec.describe Notes::PromiseFulfillmentService do
  let(:source_note) { create(:note, :with_head_revision) }
  let(:target_note) { create(:note, title: "Promessa IA", head_revision: nil) }
  let(:request_record) do
    create(
      :ai_request,
      note_revision: source_note.head_revision,
      capability: "seed_note",
      status: "succeeded",
      provider: "ollama",
      requested_provider: "ollama",
      model: "qwen2.5:1.5b",
      output_text: "# Promessa IA\n\nCorpo inicial.",
      metadata: {
        "language" => source_note.detected_language,
        "requested_by_id" => nil,
        "promise_note_id" => target_note.id,
        "promise_note_title" => target_note.title
      }
    )
  end

  it "applies the AI output to the created promise note once the request succeeds" do
    described_class.call(ai_request: request_record)

    target_note.reload
    expect(target_note.head_revision).to be_present
    expect(target_note.head_revision.content_markdown).to eq("# Promessa IA\n\nCorpo inicial.")
    expect(request_record.reload.metadata["promise_checkpoint_revision_id"]).to eq(target_note.head_revision.id)
  end

  it "does not overwrite a promise note that already has content" do
    existing_revision = create(:note_revision, note: target_note, revision_kind: :checkpoint, content_markdown: "Conteudo manual")
    target_note.update!(head_revision: existing_revision)

    described_class.call(ai_request: request_record)

    expect(target_note.reload.head_revision.content_markdown).to eq("Conteudo manual")
    expect(request_record.reload.metadata["promise_delivery_skipped_reason"]).to eq("note_already_has_content")
  end

  it "rejects invalid seed-note output before saving corrupted markdown into the promise note" do
    request_record.update!(output_text: "[[Promessa IA|nao-e-uuid]]")

    expect {
      described_class.call(ai_request: request_record)
    }.to raise_error(Ai::InvalidOutputError, /wikilink invalido/)

    expect(target_note.reload.head_revision).to be_nil
  end
end
