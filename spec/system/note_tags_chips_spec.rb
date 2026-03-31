require "rails_helper"

# Acceptance tests for note-level tag dropdown in the editor toolbar.
# Tags attached to the current note are managed via a compact dropdown.
# Users can add tags and remove them from within the dropdown.
RSpec.describe "Note tag dropdown in editor", type: :system do
  let(:user) { create(:user) }
  let!(:note) { create(:note) }
  let!(:tag_important) { create(:tag, name: "importante", color_hex: "#ef4444", tag_scope: "note") }
  let!(:tag_review) { create(:tag, name: "revisão", color_hex: "#3b82f6", tag_scope: "both") }
  let!(:tag_link_only) { create(:tag, name: "link-only", color_hex: "#10b981", tag_scope: "link") }

  before do
    login_as user, scope: :user
  end

  describe "badge count" do
    before do
      NoteTag.create!(note: note, tag: tag_important)
      NoteTag.create!(note: note, tag: tag_review)
      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 5)
    end

    it "shows the number of attached tags in the badge" do
      expect(page).to have_css("[data-note-tags-target='badge']", text: "2", wait: 3)
    end
  end

  describe "viewing tags in dropdown" do
    before do
      NoteTag.create!(note: note, tag: tag_important)
      NoteTag.create!(note: note, tag: tag_review)
      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 5)
    end

    it "shows current tags and available tags in the dropdown" do
      find("[data-note-tags-target='toggleButton']").click
      expect(page).to have_css("[data-note-tags-target='dropdown']:not(.hidden)", wait: 3)
      expect(page).to have_css(".note-tag-dropdown-item", text: "importante", wait: 3)
      expect(page).to have_css(".note-tag-dropdown-item", text: "revisão", wait: 3)
    end

    it "does not show link-only scoped tags in the dropdown" do
      find("[data-note-tags-target='toggleButton']").click
      expect(page).to have_css("[data-note-tags-target='dropdown']:not(.hidden)", wait: 3)
      expect(page).to have_no_css(".note-tag-option", text: "link-only", wait: 2)
    end
  end

  describe "adding a tag via dropdown" do
    before do
      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 5)
    end

    it "opens a dropdown with available tags when the toggle button is clicked" do
      find("[data-note-tags-target='toggleButton']").click
      expect(page).to have_css("[data-note-tags-target='dropdown']:not(.hidden)", wait: 3)
      expect(page).to have_css(".note-tag-option", text: "importante", wait: 3)
    end

    it "attaches a tag to the note and updates the badge" do
      find("[data-note-tags-target='toggleButton']").click
      expect(page).to have_css("[data-note-tags-target='dropdown']:not(.hidden)", wait: 3)

      find(".note-tag-option", text: "importante").click

      expect(page).to have_css("[data-note-tags-target='badge']", text: "1", wait: 3)
      expect(NoteTag.where(note: note, tag: tag_important)).to exist
    end

    it "hides already-attached tags from the add section" do
      NoteTag.create!(note: note, tag: tag_important)
      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 5)

      find("[data-note-tags-target='toggleButton']").click
      expect(page).to have_css("[data-note-tags-target='dropdown']:not(.hidden)", wait: 3)
      expect(page).to have_no_css(".note-tag-option", text: "importante", wait: 2)
      expect(page).to have_css(".note-tag-option", text: "revisão", wait: 3)
    end
  end

  describe "removing a tag" do
    before do
      NoteTag.create!(note: note, tag: tag_important)
      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 5)
    end

    it "removes the tag when clicking × in the dropdown" do
      find("[data-note-tags-target='toggleButton']").click
      expect(page).to have_css("[data-note-tags-target='dropdown']:not(.hidden)", wait: 3)

      within(".note-tag-dropdown-item", text: "importante") do
        find(".note-tag-chip-remove").click
      end

      expect(page).to have_no_css(".note-tag-dropdown-item", text: "importante", wait: 3)
      expect(NoteTag.where(note: note, tag: tag_important)).not_to exist
    end
  end

  describe "closing the dropdown" do
    before do
      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 5)
    end

    it "closes the dropdown when clicking outside" do
      find("[data-note-tags-target='toggleButton']").click
      expect(page).to have_css("[data-note-tags-target='dropdown']:not(.hidden)", wait: 3)

      find(".cm-content").click
      expect(page).to have_no_css("[data-note-tags-target='dropdown']:not(.hidden)", wait: 3)
    end
  end
end
