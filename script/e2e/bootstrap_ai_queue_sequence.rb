require "json"

token = ENV.fetch("E2E_TOKEN")
blank_source = ENV["BLANK_SOURCE"] == "1"
history_fixtures = ENV["HISTORY_FIXTURES"] == "1"
email = "playwright-queue-#{token}@example.test"
password = "password123"
source_title = "Playwright Queue Flow #{token}"

AiRequest.joins(note_revision: :note).where("notes.title LIKE ?", "Playwright Queue Flow #{token}%").delete_all
NoteRevision.joins(:note).where("notes.title LIKE ?", "Playwright Queue Flow #{token}%").delete_all
Note.where("title LIKE ?", "Playwright Queue Flow #{token}%").delete_all
User.where(email: email).delete_all

AiProvider.find_or_initialize_by(name: "ollama").tap do |provider|
  provider.enabled = true
  provider.base_url = "http://example.test:11434"
  provider.default_model_text = "qwen2.5:1.5b"
  provider.config = provider.config.merge("model" => "qwen2.5:1.5b", "base_url" => "http://example.test:11434")
  provider.save!
end

user = User.create!(
  email: email,
  password: password,
  password_confirmation: password
)

source_note = Note.create!(
  title: source_title,
  note_kind: "markdown",
  detected_language: "pt-BR"
)

unless blank_source
  source_revision = source_note.note_revisions.create!(
    author: user,
    revision_kind: :checkpoint,
    content_markdown: "# #{source_title}\n\nFluxo de queue Playwright."
  )
  source_note.update!(head_revision: source_revision)
end

history_fixture_labels = {}

if history_fixtures
  global_note = Note.create!(
    title: "Playwright Queue Global #{token}",
    note_kind: "markdown",
    detected_language: "pt-BR"
  )

  global_revision = global_note.note_revisions.create!(
    author: user,
    revision_kind: :checkpoint,
    content_markdown: "# Playwright Queue Global #{token}\n\nHistorico global."
  )
  global_note.update!(head_revision: global_revision)

  history_fixture_labels = {
    queued_title: "Historico Fila #{token}",
    running_title: "Historico Ativa #{token}",
    failed_title: "Historico Falha #{token}",
    succeeded_title: "Historico Concluida #{token}"
  }

  AiRequest.create!(
    note_revision: global_revision,
    capability: "seed_note",
    provider: "ollama",
    requested_provider: "ollama",
    model: "qwen2.5:1.5b",
    status: "queued",
    input_text: history_fixture_labels[:queued_title],
    metadata: {
      "language" => "pt-BR",
      "promise_note_title" => history_fixture_labels[:queued_title]
    }
  )

  AiRequest.create!(
    note_revision: global_revision,
    capability: "grammar_review",
    provider: "openai",
    requested_provider: "openai",
    model: "gpt-4o-mini",
    status: "running",
    input_text: history_fixture_labels[:running_title],
    started_at: Time.current,
    metadata: {
      "language" => "pt-BR"
    }
  )

  AiRequest.create!(
    note_revision: global_revision,
    capability: "rewrite",
    provider: "openai",
    requested_provider: "openai",
    model: "gpt-4o-mini",
    status: "failed",
    input_text: history_fixture_labels[:failed_title],
    error_message: "Falha remota de teste"
  )

  AiRequest.create!(
    note_revision: global_revision,
    capability: "translate",
    provider: "openai",
    requested_provider: "openai",
    model: "gpt-4o-mini",
    status: "succeeded",
    input_text: history_fixture_labels[:succeeded_title],
    output_text: "Translated content",
    completed_at: Time.current
  )

  10.times do |index|
    AiRequest.create!(
      note_revision: global_revision,
      capability: "rewrite",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "succeeded",
      input_text: "Historico Extra #{token} #{index}",
      output_text: "Extra #{index}",
      completed_at: Time.current - index.minutes
    )
  end
end

puts JSON.generate(
  credentials: {
    email: email,
    password: password
  },
  note_path: "/notes/#{source_note.slug}",
  blank_source: blank_source,
  history_fixtures: history_fixtures,
  history_fixture_labels: history_fixture_labels,
  promise_titles: [
    "Promessa Queue A #{token}",
    "Promessa Queue B #{token}"
  ]
)
