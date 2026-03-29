require "json"

token = ENV.fetch("E2E_TOKEN")
email = "playwright-cursor-#{token}@example.test"
password = "password123"

NoteRevision.joins(:note).where("notes.title LIKE ?", "Playwright Cursor %").delete_all
Note.where("title LIKE ?", "Playwright Cursor %").delete_all
User.where(email: email).delete_all

user = User.create!(
  email: email,
  password: password,
  password_confirmation: password
)

note = Note.create!(
  title: "Playwright Cursor #{token}",
  note_kind: "markdown",
  detected_language: "pt-BR"
)

revision = note.note_revisions.create!(
  author: user,
  revision_kind: :checkpoint,
  content_markdown: <<~MD
    ## Titulo principal

    Paragrafo com **forte**, *italico* e `codigo`.
  MD
)

note.update!(head_revision: revision)

puts JSON.generate(
  credentials: { email:, password: },
  note_path: "/notes/#{note.slug}"
)
