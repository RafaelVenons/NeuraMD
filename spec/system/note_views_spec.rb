require "rails_helper"

RSpec.describe "Note views", type: :system do
  let(:user) { create(:user) }

  before do
    login_as user, scope: :user
  end

  def create_noted(title, content: "Conteudo de #{title}")
    note = create(:note, title: title)
    Notes::CheckpointService.call(note: note, content: content, author: user)
    note.reload
  end

  describe "index page" do
    it "shows existing views and a create form" do
      create(:note_view, name: "Neuro Notes")
      visit note_views_path

      expect(page).to have_text("Neuro Notes")
      expect(page).to have_css(".nv-form")
    end

    it "shows empty state when no views exist" do
      visit note_views_path
      expect(page).to have_text("Nenhuma view criada")
    end
  end

  describe "navigation" do
    it "shows Views link in the nav bar" do
      visit note_views_path
      expect(page).to have_link("Views", href: note_views_path)
    end
  end

  describe "table view" do
    it "displays filtered notes in a table" do
      tag = create(:tag, name: "neuro")
      tagged = create_noted("Neurociencia Basica")
      NoteTag.create!(note: tagged, tag: tag)
      _other = create_noted("Cardiologia")

      view = create(:note_view,
        name: "Neuro View",
        filter_query: "tag:neuro",
        columns: ["title", "updated_at"])

      visit note_view_path(view)

      expect(page).to have_text("Neuro View", wait: 5)
      expect(page).to have_css(".nv-table", wait: 10)
      expect(page).to have_css(".nv-table__link", text: "Neurociencia Basica")
      expect(page).not_to have_text("Cardiologia")
    end

    it "shows empty state for no matching notes" do
      view = create(:note_view, name: "Empty View", filter_query: "tag:nonexistent")
      visit note_view_path(view)

      expect(page).to have_text("Nenhuma nota encontrada", wait: 10)
    end
  end

  describe "card view" do
    it "displays notes as cards" do
      note = create_noted("Card Note", content: "Este e o conteudo do card para teste")
      view = create(:note_view, name: "Card View", display_type: "card", columns: ["title", "updated_at"])

      visit note_view_path(view)

      expect(page).to have_css(".nv-cards", wait: 10)
      expect(page).to have_css(".nv-card__title", text: "Card Note")
    end
  end

  describe "list view" do
    it "displays notes as a compact list" do
      note = create_noted("List Note")
      view = create(:note_view, name: "List View", display_type: "list", columns: ["title", "updated_at"])

      visit note_view_path(view)

      expect(page).to have_css(".nv-list", wait: 10)
      expect(page).to have_css(".nv-list__title", text: "List Note")
    end
  end

  describe "display type switching" do
    it "switches between table and card views" do
      create_noted("Switch Note")
      view = create(:note_view, name: "Switch View", display_type: "table", columns: ["title", "updated_at"])

      visit note_view_path(view)
      expect(page).to have_css(".nv-table", wait: 10)

      click_button "Cards"
      expect(page).to have_css(".nv-cards", wait: 5)
    end
  end

  describe "sorting" do
    it "sorts by clicking column header" do
      create_noted("Zebra")
      create_noted("Alpha")
      view = create(:note_view,
        name: "Sort View",
        columns: ["title", "updated_at"],
        sort_config: {"field" => "updated_at", "direction" => "desc"})

      visit note_view_path(view)
      expect(page).to have_css(".nv-table__link", text: "Zebra", wait: 10)

      # Click title header to sort by title
      find("th", text: /Titulo/i).click

      # Wait for re-render — sort icon should appear
      expect(page).to have_css(".nv-table__sort-icon", text: "▲", wait: 10)
    end
  end

  describe "filter editing" do
    it "updates results when filter is changed" do
      tag = create(:tag, name: "neuro")
      tagged = create_noted("Neurociencia")
      NoteTag.create!(note: tagged, tag: tag)
      _other = create_noted("Cardiologia")

      view = create(:note_view, name: "Filter Test", filter_query: "", columns: ["title", "updated_at"])

      visit note_view_path(view)
      expect(page).to have_css(".nv-table", wait: 10)
      # Both notes should appear initially
      expect(page).to have_text("Neurociencia")
      expect(page).to have_text("Cardiologia")

      # Update filter
      filter_input = find("[data-note-view-target='filterInput']")
      filter_input.fill_in with: "tag:neuro"
      filter_input.send_keys(:return)

      # Wait for filtered results
      expect(page).to have_css(".nv-table__link", text: "Neurociencia", wait: 10)
      expect(page).not_to have_text("Cardiologia")
    end
  end
end
