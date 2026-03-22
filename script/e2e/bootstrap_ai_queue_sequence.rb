require "json"

token = ENV.fetch("E2E_TOKEN")
blank_source = ENV["BLANK_SOURCE"] == "1"
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

puts JSON.generate(
  credentials: {
    email: email,
    password: password
  },
  note_path: "/notes/#{source_note.slug}",
  blank_source: blank_source,
  promise_titles: [
    "Promessa Queue A #{token}",
    "Promessa Queue B #{token}"
  ]
)
