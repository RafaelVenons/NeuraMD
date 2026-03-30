require "json"

token = ENV.fetch("E2E_TOKEN")
email = "playwright-leak-#{token}@example.test"
password = "password123"

NoteRevision.joins(:note).where("notes.title LIKE ?", "Playwright Leak %").delete_all
Note.where("title LIKE ?", "Playwright Leak %").delete_all
User.where(email: email).delete_all

user = User.create!(
  email: email,
  password: password,
  password_confirmation: password
)

target = Note.create!(
  title: "Playwright Leak Target #{token}",
  note_kind: "markdown",
  detected_language: "pt-BR"
)

note = Note.create!(
  title: "Playwright Leak #{token}",
  note_kind: "markdown",
  detected_language: "pt-BR"
)

revision = note.note_revisions.create!(
  author: user,
  revision_kind: :checkpoint,
  content_markdown: <<~MD
    ## Titulo principal

    Paragrafo com **forte**, *italico*, `codigo` e [[Destino|#{target.id}]]

    > citacao importante

    - item solto
    7. item ordenado

    ```ruby
    puts '**nao formatar**'
    ```
  MD
)

note.update!(head_revision: revision)

puts JSON.generate(
  credentials: { email:, password: },
  note_path: "/notes/#{note.slug}",
  target_title: target.title
)
