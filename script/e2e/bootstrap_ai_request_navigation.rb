require "json"

token = ENV.fetch("E2E_TOKEN")
email = "playwright-nav-#{token}@example.test"
password = "password123"

AiRequest.joins(note_revision: :note).where("notes.title LIKE ?", "Playwright Nav %").delete_all
NoteRevision.joins(:note).where("notes.title LIKE ?", "Playwright Nav %").delete_all
Note.where("title LIKE ?", "Playwright Nav %").delete_all
User.where(email: email).delete_all

user = User.create!(
  email: email,
  password: password,
  password_confirmation: password
)

current_note = Note.create!(
  title: "Playwright Nav Atual #{token}",
  note_kind: "markdown",
  detected_language: "pt-BR"
)
current_revision = current_note.note_revisions.create!(
  author: user,
  revision_kind: :checkpoint,
  content_markdown: "# Atual\n\nNota aberta inicialmente."
)
current_note.update!(head_revision: current_revision)

source_note = Note.create!(
  title: "Playwright Nav Origem #{token}",
  note_kind: "markdown",
  detected_language: "pt-BR"
)
source_revision = source_note.note_revisions.create!(
  author: user,
  revision_kind: :checkpoint,
  content_markdown: "# Origem\n\nTexto original da nota de origem."
)
source_note.update!(head_revision: source_revision)

translated_note = Note.create!(
  title: "Playwright Nav Translation #{token}",
  note_kind: "markdown",
  detected_language: "en-US"
)
translated_revision = translated_note.note_revisions.create!(
  author: user,
  revision_kind: :checkpoint,
  content_markdown: "# Translation\n\nAlready created translation."
)
translated_note.update!(head_revision: translated_revision)

promise_note = Note.create!(
  title: "Playwright Nav Promise #{token}",
  note_kind: "markdown",
  detected_language: "pt-BR"
)
promise_revision = promise_note.note_revisions.create!(
  author: user,
  revision_kind: :checkpoint,
  ai_generated: true,
  content_markdown: "# Playwright Nav Promise #{token}\n\nConteudo da promise."
)
promise_note.update!(head_revision: promise_revision)

rewrite_request = AiRequest.create!(
  note_revision: source_revision,
  capability: "rewrite",
  provider: "openai",
  requested_provider: "openai",
  model: "gpt-4o-mini",
  status: "succeeded",
  input_text: "Texto original da nota de origem.",
  output_text: "Texto revisado da nota de origem.",
  completed_at: Time.current
)

grammar_request = AiRequest.create!(
  note_revision: source_revision,
  capability: "grammar_review",
  provider: "openai",
  requested_provider: "openai",
  model: "gpt-4o-mini",
  status: "succeeded",
  input_text: "Texto original da nota de origem.",
  output_text: "Texto corrigido da nota de origem.",
  completed_at: Time.current
)

translate_request = AiRequest.create!(
  note_revision: source_revision,
  capability: "translate",
  provider: "openai",
  requested_provider: "openai",
  model: "gpt-4o-mini",
  status: "succeeded",
  input_text: "# Origem\n\nTexto original da nota de origem.",
  output_text: "# Translation\n\nAlready created translation.",
  completed_at: Time.current,
  metadata: {
    "language" => "pt-BR",
    "target_language" => "en-US",
    "translated_note_id" => translated_note.id
  }
)

seed_request = AiRequest.create!(
  note_revision: source_revision,
  capability: "seed_note",
  provider: "ollama",
  requested_provider: "ollama",
  model: "qwen2.5:1.5b",
  status: "succeeded",
  input_text: "Gerar promessa",
  output_text: promise_revision.content_markdown,
  completed_at: Time.current,
  metadata: {
    "language" => "pt-BR",
    "promise_note_id" => promise_note.id,
    "promise_note_title" => promise_note.title
  }
)

puts JSON.generate(
  credentials: {
    email: email,
    password: password
  },
  current_note_path: "/notes/#{current_note.slug}",
  source_note_path: "/notes/#{source_note.slug}",
  translated_note_path: "/notes/#{translated_note.slug}",
  promise_note_path: "/notes/#{promise_note.slug}",
  requests: {
    rewrite: rewrite_request.id,
    grammar_review: grammar_request.id,
    translate: translate_request.id,
    seed_note: seed_request.id
  },
  titles: {
    source: source_note.title,
    translated: translated_note.title,
    promise: promise_note.title
  },
  outputs: {
    rewrite: rewrite_request.output_text,
    grammar_review: grammar_request.output_text,
    seed_note: "Conteudo da promise."
  }
)
