require "json"

token = ENV.fetch("E2E_TOKEN")
email = "playwright-#{token}@example.test"
password = "password123"

AiRequest.joins(note_revision: :note).where("notes.title LIKE ?", "Playwright %").delete_all
NoteRevision.joins(:note).where("notes.title LIKE ?", "Playwright %").delete_all
Note.where("title LIKE ?", "Playwright %").delete_all
User.where("email LIKE ?", "playwright-%@example.test").delete_all

user = User.create!(
  email:,
  password: password,
  password_confirmation: password
)

source_note = Note.create!(
  title: "Playwright Fonte #{token}",
  note_kind: "markdown",
  detected_language: "pt-BR"
)

source_revision = source_note.note_revisions.create!(
  author: user,
  revision_kind: :checkpoint,
  content_markdown: <<~MD
    [[Promessa Playwright A]]

    [[Promessa Playwright B]]
  MD
)
source_note.update!(head_revision: source_revision)

created_note = Note.create!(
  title: "Playwright Criada #{token}",
  note_kind: "markdown",
  detected_language: "pt-BR"
)

created_revision = created_note.note_revisions.create!(
  author: user,
  revision_kind: :checkpoint,
  ai_generated: true,
  content_markdown: "Conteudo criado pela IA no cenario Playwright."
)
created_note.update!(head_revision: created_revision)

queued_request = AiRequest.create!(
  note_revision: source_revision,
  capability: "seed_note",
  provider: "ollama",
  requested_provider: "ollama",
  model: "qwen2.5:1.5b",
  status: "queued",
  queue_position: 1,
  input_text: "Gerar nota A",
  metadata: {
    "language" => "pt-BR",
    "promise_note_title" => "Promessa Playwright A"
  }
)

running_request = AiRequest.create!(
  note_revision: source_revision,
  capability: "seed_note",
  provider: "ollama",
  requested_provider: "ollama",
  model: "qwen2.5:1.5b",
  status: "running",
  queue_position: 2,
  input_text: "Gerar nota B",
  started_at: Time.current - 20.seconds,
  metadata: {
    "language" => "pt-BR",
    "promise_note_title" => "Promessa Playwright B"
  }
)

completed_seed_request = AiRequest.create!(
  note_revision: source_revision,
  capability: "seed_note",
  provider: "ollama",
  requested_provider: "ollama",
  model: "qwen2.5:1.5b",
  status: "succeeded",
  queue_position: 3,
  input_text: "Gerar nota criada",
  output_text: created_revision.content_markdown,
  completed_at: Time.current - 5.seconds,
  metadata: {
    "language" => "pt-BR",
    "promise_note_id" => created_note.id,
    "promise_note_title" => created_note.title
  }
)

failed_request = AiRequest.create!(
  note_revision: source_revision,
  capability: "grammar_review",
  provider: "openai",
  requested_provider: "openai",
  model: "gpt-4o-mini",
  status: "failed",
  queue_position: 4,
  input_text: "Texto original com erro.",
  attempts_count: 1,
  error_message: "Falha simulada no provider.",
  last_error_kind: "transient",
  completed_at: Time.current - 2.seconds,
  metadata: {
    "language" => "pt-BR"
  }
)

puts JSON.generate({
  credentials: {
    email: email,
    password: password
  },
  note_path: "/notes/#{source_note.slug}",
  created_note_path: "/notes/#{created_note.slug}",
  completed_seed_request_id: completed_seed_request.id,
  queue_cards: [
    { id: queued_request.id, title: "Promessa Playwright A", status_label: "Criar" },
    { id: running_request.id, title: "Promessa Playwright B", status_label: "Criando" },
    { id: completed_seed_request.id, title: created_note.title, status_label: "Criado" },
    { id: failed_request.id, title: source_note.title, status_label: "Revisar" }
  ]
})
