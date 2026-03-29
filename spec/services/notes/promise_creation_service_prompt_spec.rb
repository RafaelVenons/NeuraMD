require "rails_helper"

RSpec.describe Notes::PromiseCreationService, "prompt_input" do
  let(:author) { create(:user) }
  let(:source_note) { create(:note, :with_head_revision, title: "Work Projects", detected_language: "pt-BR") }

  before do
    allow(Ai::ProviderRegistry).to receive(:enabled?).and_return(true)
    allow(Ai::ReviewService).to receive(:enqueue).and_return(
      create(:ai_request, note_revision: source_note.head_revision, capability: "seed_note")
    )
  end

  it "puts the new note title as the primary topic" do
    described_class.call(source_note:, title: "Friends", author:, mode: "ai")

    expect(Ai::ReviewService).to have_received(:enqueue).with(
      hash_including(text: a_string_matching(/Write a markdown note about: Friends/))
    )
  end

  it "states the title is the only topic" do
    described_class.call(source_note:, title: "Friends", author:, mode: "ai")

    expect(Ai::ReviewService).to have_received(:enqueue).with(
      hash_including(text: a_string_matching(/ENTIRELY about "Friends"/))
    )
  end

  it "includes source content only as style reference, not topic" do
    described_class.call(source_note:, title: "Friends", author:, mode: "ai")

    expect(Ai::ReviewService).to have_received(:enqueue).with(
      hash_including(text: a_string_matching(/Style reference.*do NOT write about this content/))
    )
  end

  it "truncates source excerpt to 300 characters" do
    long_content = "A" * 500
    source_note.head_revision.update!(content_markdown: long_content)

    described_class.call(source_note:, title: "Topic", author:, mode: "ai")

    expect(Ai::ReviewService).to have_received(:enqueue).with(
      hash_including(text: a_string_matching(/Source excerpt: A{1,300}\.{3}/))
    )
  end

  it "omits source context when content is too short" do
    source_note.head_revision.update!(content_markdown: "Hi")

    described_class.call(source_note:, title: "Topic", author:, mode: "ai")

    expect(Ai::ReviewService).to have_received(:enqueue).with(
      hash_including(text: a_string_not_matching(/Style reference/))
    )
  end

  it "includes detected language" do
    described_class.call(source_note:, title: "Amigos", author:, mode: "ai")

    expect(Ai::ReviewService).to have_received(:enqueue).with(
      hash_including(text: a_string_matching(/Language: pt-BR/))
    )
  end
end

RSpec::Matchers.define :a_string_not_matching do |regex|
  match { |actual| actual.is_a?(String) && !actual.match?(regex) }
end
