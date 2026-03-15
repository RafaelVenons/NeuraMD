require "rails_helper"

RSpec.describe "Note finder", type: :system do
  let(:user) { create(:user) }
  let!(:title_match) { create(:note, :with_head_revision, title: "Cardio Guia") }
  let!(:content_match) do
    note = create(:note, title: "Neurologia")
    revision = create(:note_revision, note: note, content_markdown: "Paciente com arritmia recorrente em observacao")
    note.update_columns(head_revision_id: revision.id)
    note
  end

  before do
    login_as user, scope: :user
  end

  def search_in_finder(query)
    input = find("[data-note-finder-target='input']")
    input.click
    input.send_keys(query)
    expect(page).to have_css(".note-finder-result", text: "Neurologia", wait: 5)
  end

  it "opens from the layout and navigates to a searched note" do
    visit graph_path

    find("button[data-action='click->note-finder#open']").click
    expect(page).to have_css("[data-note-finder-target='dialog']:not(.hidden)", wait: 3)

    search_in_finder("arritmia")
    expect(page).to have_text("Paciente com arritmia recorrente", wait: 3)

    find("[data-note-finder-target='input']").send_keys(:enter)
    expect(page).to have_current_path(note_path(content_match.slug), wait: 5)
  end

  it "navigates by mouse click on a finder result" do
    visit graph_path

    find("button[data-action='click->note-finder#open']").click
    expect(page).to have_css("[data-note-finder-target='dialog']:not(.hidden)", wait: 3)

    search_in_finder("arritmia")
    find(".note-finder-result", text: "Neurologia").click
    expect(page).to have_current_path(note_path(content_match.slug), wait: 5)
  end
end
