require "rails_helper"

# Acceptance tests for note-to-note navigation.
# When the user clicks a wiki-link in the preview pane or a backlink, the
# current note must be saved (draft) BEFORE navigation, and the destination
# note must open with the preview pane visible.
RSpec.describe "Note navigation via links", type: :system do
  let(:user) { create(:user) }
  let!(:dest_note) { create(:note, title: "Nota Destino") }

  def editor
    find(".cm-content")
  end

  before do
    login_as user, scope: :user
  end

  # ── Preview wikilink click ───────────────────────────────────────────────

  describe "clicking a wiki-link in the preview pane" do
    let!(:src_note) { create(:note) }

    before do
      visit note_path(src_note.slug)
      expect(page).to have_css(".cm-editor", wait: 5)
    end

    it "saves the current note as draft before navigating" do
      # Type content that includes a wiki-link to dest_note
      editor.click
      editor.send_keys("Conteúdo importante [[Destino|#{dest_note.id}]]")

      # Wait for preview to render the wiki-link
      expect(page).to have_css(".preview-prose a.wikilink", wait: 3)

      # Click the wiki-link
      find(".preview-prose a.wikilink").click

      # After navigation, verify source note has a draft revision saved
      expect(page).to have_current_path(note_path(dest_note.slug), wait: 5)
      src_note.reload
      expect(src_note.note_revisions.where(revision_kind: :draft)).to exist
    end

    it "opens the destination note with the preview pane visible" do
      editor.click
      editor.send_keys("Veja [[Destino|#{dest_note.id}]]")
      expect(page).to have_css(".preview-prose a.wikilink", wait: 3)

      find(".preview-prose a.wikilink").click

      expect(page).to have_current_path(note_path(dest_note.slug), wait: 5)
      # Preview pane must be visible (not hidden)
      expect(page).to have_css("#preview-pane:not(.hidden)", wait: 3)
    end

    it "renders the destination note content in the preview after navigation" do
      # Give dest_note actual markdown content via a checkpoint
      Notes::CheckpointService.call(
        note: dest_note,
        content: "# Título Destino\n\nConteúdo da nota destino.",
        author: user
      )

      editor.click
      editor.send_keys("Veja [[Nota Destino|#{dest_note.id}]]")
      expect(page).to have_css(".preview-prose a.wikilink", wait: 3)

      find(".preview-prose a.wikilink").click

      expect(page).to have_current_path(note_path(dest_note.slug), wait: 5)
      # Regression guard: preview must show the note content — not the blank placeholder.
      # This verifies the codemirror:change initial dispatch reaches preview_controller
      # even after Turbo navigation (setTimeout(0) fix in codemirror_controller).
      expect(page).to have_css(".preview-prose h1", text: "Título Destino", wait: 5)
      expect(page).not_to have_text("Comece a digitar para ver o preview")
    end
  end

  # ── Backlink click ───────────────────────────────────────────────────────

  describe "clicking a backlink" do
    # src_note has a saved wiki-link to dest_note so dest_note shows backlinks
    let!(:src_note) do
      n = create(:note)
      Notes::CheckpointService.call(
        note: n,
        content: "Referência [[Dest|#{dest_note.id}]]",
        author: create(:user)
      )
      n
    end

    before do
      visit note_path(dest_note.slug)
      expect(page).to have_css(".cm-editor", wait: 5)
    end

    it "saves the current note as draft before navigating via backlink" do
      # Type something so there's pending content
      editor.click
      editor.send_keys("Conteúdo não salvo")

      # Backlinks panel should show src_note as a backlink
      expect(page).to have_css(".backlinks-panel a", wait: 3)

      find(".backlinks-panel a", text: src_note.title).click

      expect(page).to have_current_path(note_path(src_note.slug), wait: 5)
      dest_note.reload
      expect(dest_note.note_revisions.where(revision_kind: :draft)).to exist
    end
  end
end
