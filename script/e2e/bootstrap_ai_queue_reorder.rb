require "json"

token = ENV.fetch("E2E_TOKEN")
email = "playwright-reorder-#{token}@example.test"
password = "password123"

AiRequest.joins(note_revision: :note).where("notes.title LIKE ?", "Playwright Reorder %").delete_all
NoteRevision.joins(:note).where("notes.title LIKE ?", "Playwright Reorder %").delete_all
Note.where("title LIKE ?", "Playwright Reorder %").delete_all
User.where(email: email).delete_all

user = User.create!(
  email: email,
  password: password,
  password_confirmation: password
)

note = Note.create!(
  title: "Playwright Reorder Fonte #{token}",
  note_kind: "markdown",
  detected_language: "pt-BR"
)

revision = note.note_revisions.create!(
  author: user,
  revision_kind: :checkpoint,
  content_markdown: "# Playwright Reorder\n\nFila para reorder."
)
note.update!(head_revision: revision)

[
  ["Fila Baixa #{token}", 1],
  ["Fila Media #{token}", 2],
  ["Fila Alta #{token}", 3]
].each do |title, position|
  AiRequest.create!(
    note_revision: revision,
    capability: "grammar_review",
    provider: "openai",
    requested_provider: "openai",
    model: "gpt-4o-mini",
    status: "queued",
    queue_position: position,
    input_text: "Texto #{title}",
    metadata: {
      "language" => "pt-BR",
      "promise_note_title" => title
    }
  )
end

puts JSON.generate(
  credentials: {
    email: email,
    password: password
  },
  note_path: "/notes/#{note.slug}",
  titles: {
    low: "Fila Baixa #{token}",
    mid: "Fila Media #{token}",
    high: "Fila Alta #{token}"
  }
)
