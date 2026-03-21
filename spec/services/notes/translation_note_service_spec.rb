require "rails_helper"

RSpec.describe Notes::TranslationNoteService do
  let(:author) { create(:user) }
  let(:source_note) { create(:note, :with_head_revision, title: "Resumo Clínico", detected_language: "pt-BR") }
  let(:request_record) do
    create(
      :ai_request,
      note_revision: source_note.head_revision,
      capability: "translate",
      status: "succeeded",
      provider: "ollama",
      requested_provider: "ollama",
      model: "qwen2:1.5b",
      output_text: "Clinical Summary"
    )
  end

  it "creates a translated note with a backlink footer to the source note" do
    translated_note = described_class.call(
      source_note: source_note,
      ai_request: request_record,
      content: "# Clinical Summary\n\nTranslated content.",
      target_language: "en-US",
      author: author
    )

    expect(translated_note).to be_persisted
    expect(translated_note.detected_language).to eq("en-US")
    expect(translated_note.title).to eq("Resumo Clínico (English)")
    expect(translated_note.head_revision.content_markdown).to include("Translated content.")
    expect(translated_note.head_revision.content_markdown).to include("Traduzida de [[Resumo Clínico|b:#{source_note.id}]]")

    expect(source_note.outgoing_links.find_by(dst_note: translated_note)).to be_nil
    expect(translated_note.outgoing_links.find_by(dst_note: source_note, hier_role: "same_level")).to be_present
    expect(request_record.reload.metadata).to include("translated_note_id" => translated_note.id)
  end

  it "returns the previously created translated note for the same request" do
    first_note = described_class.call(
      source_note: source_note,
      ai_request: request_record,
      content: "# Clinical Summary\n\nTranslated content.",
      target_language: "en-US",
      author: author
    )

    second_note = described_class.call(
      source_note: source_note,
      ai_request: request_record,
      content: "# Ignored\n\nDifferent text.",
      target_language: "en-US",
      author: author
    )

    expect(second_note.id).to eq(first_note.id)
  end
end
