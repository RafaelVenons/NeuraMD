require "rails_helper"

RSpec.describe "Note finder DSL", type: :system do
  let(:user) { create(:user) }

  before do
    login_as user, scope: :user
  end

  def open_finder
    page.send_keys [:control, :shift, "k"]
    expect(page).to have_css(".note-finder-panel", wait: 5)
  end

  def finder_input
    find("[data-note-finder-target='input']")
  end

  describe "DSL search" do
    it "filters notes by tag operator" do
      note = create(:note, title: "Neurociencia Avancada")
      Notes::CheckpointService.call(note: note, content: "Estudo de neurociencia", author: user)
      tag = create(:tag, name: "neuro")
      NoteTag.create!(note: note, tag: tag)

      other = create(:note, title: "Cardiologia Basica")
      Notes::CheckpointService.call(note: other, content: "Estudo de cardiologia", author: user)

      visit root_path
      open_finder
      finder_input.fill_in with: "tag:neuro"
      finder_input.send_keys(:return) # trigger search

      expect(page).to have_css(".note-finder-result__title", text: "Neurociencia Avancada", wait: 5)
      expect(page).not_to have_css(".note-finder-result__title", text: "Cardiologia Basica")
    end

    it "combines DSL filter with text search" do
      tag = create(:tag, name: "medicina")

      match = create(:note, title: "Hematologia Clinica")
      Notes::CheckpointService.call(note: match, content: "Estudo de hematologia clinica", author: user)
      NoteTag.create!(note: match, tag: tag)

      no_match = create(:note, title: "XYZQWK Topico Totalmente Diferente")
      Notes::CheckpointService.call(note: no_match, content: "Conteudo totalmente irrelevante sem relacao", author: user)
      NoteTag.create!(note: no_match, tag: tag)

      visit root_path
      open_finder
      finder_input.fill_in with: "tag:medicina Hematologia"

      expect(page).to have_css(".note-finder-result__title", text: "Hematologia Clinica", wait: 5)
      expect(page).not_to have_css(".note-finder-result__title", text: "XYZQWK")
    end

    it "searches normally without DSL operators (regression)" do
      note = create(:note, title: "Neurologia Simples")
      Notes::CheckpointService.call(note: note, content: "Texto sobre neurologia", author: user)

      visit root_path
      open_finder
      finder_input.fill_in with: "Neurologia"

      expect(page).to have_css(".note-finder-result__title", text: "Neurologia Simples", wait: 5)
    end
  end

  describe "operator suggestions" do
    it "shows operator suggestions when typing a partial match" do
      visit root_path
      open_finder
      finder_input.fill_in with: "ta"

      expect(page).to have_css(".note-finder-suggestion", text: "tag:", wait: 3)
    end

    it "hides suggestions when operator is complete" do
      visit root_path
      open_finder
      finder_input.fill_in with: "tag:"

      expect(page).not_to have_css(".note-finder-suggestion")
    end
  end

  describe "DSL error feedback" do
    it "shows error for invalid operator value" do
      create(:note, :with_head_revision, title: "Test Note")

      visit root_path
      open_finder
      finder_input.fill_in with: "orphan:maybe test"

      expect(page).to have_css(".note-finder-dsl-error", wait: 5)
    end
  end
end
