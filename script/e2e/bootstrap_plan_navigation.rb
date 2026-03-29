require "json"
require "stringio"

token = ENV.fetch("E2E_TOKEN")
email = "playwright-plan-#{token}@example.test"
password = "password123"

User.where(email: email).delete_all

user = User.create!(
  email: email,
  password: password,
  password_confirmation: password
)

original_stdout = $stdout
$stdout = StringIO.new
load Rails.root.join("script/import_plan_to_notes.rb")
$stdout = original_stdout

root_note = Note.joins(:tags).where(tags: { name: "plan" }).find_by!(title: "PLAN — NeuraMD (Rails 8, Hotwire, PostgreSQL, Self-Hosted)")
target_note = Note.joins(:tags).where(tags: { name: "plan" }).find_by!(title: "11. Plano Incremental de Execução")
child_note = Note.joins(:tags).where(tags: { name: "plan" }).find_by!(title: "11.1 Ordem de Implementação Técnica das Prioridades Atuais")

puts JSON.generate(
  credentials: { email:, password: },
  root_note_path: "/notes/#{root_note.slug}",
  target_note_path: "/notes/#{target_note.slug}",
  child_note_path: "/notes/#{child_note.slug}",
  target_note_title: target_note.title,
  child_note_title: child_note.title
)
