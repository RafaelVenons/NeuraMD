require "rails_helper"

# Acceptance tests for note-to-note navigation.
# When the user clicks a wiki-link in the preview pane or a backlink, the
# current note must be saved (draft) BEFORE navigation, and the destination
# note must open with the preview pane visible.
RSpec.describe "Note navigation via links", type: :system do
  let(:user) { create(:user) }
  let!(:dest_note) { create(:note, title: "Nota Destino") }
  let!(:long_title_dest_note) { create(:note, title: "AIrch Long Validation 1774009721") }

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

    it "navigates correctly when the preview link points to a long title with numbers" do
      editor.click
      editor.send_keys("[[AIrch Long Validation 1774009721|#{long_title_dest_note.id}]]")
      expect(page).to have_css(".preview-prose a.wikilink", text: "AIrch Long Validation 1774009721", wait: 5)

      find(".preview-prose a.wikilink", text: "AIrch Long Validation 1774009721").click

      expect(page).to have_current_path(note_path(long_title_dest_note.slug), wait: 5)
    end

    it "prefers newer local content on reopen and saves that version before navigation" do
      Notes::CheckpointService.call(
        note: src_note,
        content: "Versao servidor [[Destino|#{dest_note.id}]]",
        author: user
      )

      visit note_path(src_note.slug)
      expect(page).to have_css(".cm-editor", wait: 5)

      page.execute_script(<<~JS)
        localStorage.setItem("note-draft-#{src_note.id}", JSON.stringify({
          content: "Versao local nova [[Destino|#{dest_note.id}]]",
          savedAt: Date.now() + 60_000
        }))
      JS

      visit current_path
      expect(page).to have_css(".preview-prose a.wikilink", wait: 5)
      expect(page).to have_text("Versao local nova", wait: 5)

      find(".preview-prose a.wikilink").click

      expect(page).to have_current_path(note_path(dest_note.slug), wait: 5)
      src_note.reload
      expect(src_note.note_revisions.where(revision_kind: :draft).last.content_markdown).to include("Versao local nova")
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

      # Switch footer to backlinks mode
      find("select[data-editor-target='contextMode']").select("Backlinks")

      # Backlinks panel should show src_note as a backlink
      expect(page).to have_css(".backlinks-panel a", wait: 5)

      find(".backlinks-panel a", text: src_note.title).click

      expect(page).to have_current_path(note_path(src_note.slug), wait: 5)
      dest_note.reload
      expect(dest_note.note_revisions.where(revision_kind: :draft)).to exist
    end
  end

  describe "revision history dropdown" do
    let!(:note_with_revisions) do
      note = create(:note)
      Notes::CheckpointService.call(note: note, content: "Primeira versao", author: user)
      Notes::CheckpointService.call(note: note, content: "Segunda versao", author: user)
      note
    end

    before do
      visit note_path(note_with_revisions.slug)
      expect(page).to have_css(".cm-editor", wait: 5)
    end

    it "opens a dropdown from the clock button and lists saved revisions" do
      find("[data-editor-target='revisionsButton']").click

      expect(page).to have_css("[data-editor-target='revisionsMenu']:not(.hidden)", wait: 3)
      expect(page).to have_css("[data-revision-id]", count: 2, wait: 3)
      expect(page).not_to have_button("Abrir")
    end

    it "previews a historical revision on hover and restores the current content on mouse leave" do
      revision = note_with_revisions.note_revisions.where(revision_kind: :checkpoint).order(:created_at).first

      expect(page).to have_text("Segunda versao")

      find("[data-editor-target='revisionsButton']").click
      find("[data-revision-id='#{revision.id}']").hover

      expect(page).to have_text("Primeira versao")

      find("body").hover

      expect(page).to have_text("Segunda versao")
    end

    it "keeps the clicked historical revision in the editor and offers restore until edited" do
      revision = note_with_revisions.note_revisions.where(revision_kind: :checkpoint).order(:created_at).first

      find("[data-editor-target='revisionsButton']").click
      find("[data-revision-id='#{revision.id}']").click

      expect(page).to have_current_path(note_path(note_with_revisions.slug), wait: 5)
      expect(page).to have_text("Primeira versao")
      expect(page).to have_button("Restaurar")

      find(".cm-content").click
      find(".cm-content").send_keys(" editada")

      expect(page).to have_button("Salvar")
    end

    it "shows restore instead of save when loading an old revision without edits" do
      revision = note_with_revisions.note_revisions.where(revision_kind: :checkpoint).order(:created_at).first

      visit revision_note_path(note_with_revisions.slug, revision_id: revision.id)

      expect(page).to have_button("Restaurar", wait: 5)
    end
  end

  describe "revision property diff badges" do
    let!(:note_with_props) do
      note = create(:note)
      Notes::CheckpointService.call(note: note, content: "v1", author: user,
        properties_data: {"status" => "draft"})
      Notes::CheckpointService.call(note: note, content: "v2", author: user,
        properties_data: {"status" => "published", "priority" => 1})
      note
    end

    before do
      visit note_path(note_with_props.slug)
      expect(page).to have_css(".cm-editor", wait: 5)
    end

    it "shows property diff badges in the revision dropdown" do
      find("[data-editor-target='revisionsButton']").click
      expect(page).to have_css("[data-editor-target='revisionsMenu']:not(.hidden)", wait: 3)

      within("[data-editor-target='revisionsMenu']") do
        expect(page).to have_text("+priority")
        expect(page).to have_text("~status")
      end
    end
  end
end
