require "rails_helper"
require "stringio"
require "uri"

RSpec.describe "New specs navigation", type: :system do
  let(:user) { create(:user) }

  before do
    login_as user, scope: :user

    original_stdout = $stdout
    $stdout = StringIO.new
    load Rails.root.join("script/import_new_specs_to_notes.rb")
    $stdout = original_stdout
  end

  def visible_editor_text
    page.evaluate_script(<<~JS)
      (() => {
        const content = document.querySelector("#codemirror-host .cm-content")
        if (!content) return null

        return Array.from(content.querySelectorAll(".cm-line"))
          .filter((line) => {
            const style = window.getComputedStyle(line)
            return style.display !== "none" &&
              style.visibility !== "hidden" &&
              style.opacity !== "0" &&
              style.color !== "rgba(0, 0, 0, 0)"
          })
          .map((line) => line.textContent)
          .join("\\n")
      })()
    JS
  end

  it "opens an imported new-specs note and follows a sequential child link" do
    imported_notes = Note.joins(:tags).where(tags: { name: "new-specs" })
    target_note = imported_notes.where("notes.title like ?", "%Fase 1 — Propriedades tipadas por nota%").order(:title).first!

    visit note_path(target_note.slug)

    expect(page).to have_css(".cm-editor", wait: 5)
    expect(find("[data-editor-target='titleInput']").value).to eq(target_note.title)
    expect(visible_editor_text).to include("##")
    expect(page).not_to have_text("We're sorry, but something went wrong.")

    find(".cm-content").click
    find(".cm-content").send_keys(" ", :backspace)
    child_path = URI.parse(find(".preview-prose ol a", match: :first, wait: 5)[:href]).path
    child_slug = child_path.split("/").last
    child_note = Note.find_by!(slug: child_slug)

    find(".preview-prose ol a", match: :first).click

    expect(page).to have_current_path(note_path(child_note.slug), wait: 5)
    expect(find("[data-editor-target='titleInput']").value).to eq(child_note.title)
    expect(page).to have_css(".cm-editor", wait: 5)
    expect(visible_editor_text).to include(child_note.head_revision.content_markdown.lines.first.to_s.strip)
    expect(page).not_to have_text("We're sorry, but something went wrong.")
  end
end
