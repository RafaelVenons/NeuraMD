require "rails_helper"

RSpec.describe "Render pipeline", type: :system do
  let(:user) { create(:user) }

  before do
    login_as user, scope: :user
  end

  def trigger_preview
    find(".cm-content").click
    find(".cm-content").send_keys(" ")
  end

  # ── EPIC-04.1: Renderer contract ─────────────────────────────────────────

  describe "renderer isolation" do
    it "shows fallback when a renderer throws, without breaking other renderers" do
      note = create(:note)
      Notes::CheckpointService.call(
        note: note,
        content: "# Heading Normal\n\nTexto com **negrito** e `codigo`.",
        author: user
      )

      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 10)
      trigger_preview
      expect(page).to have_css(".preview-prose h1", text: "Heading Normal", wait: 5)

      # Inject a broken renderer into the pipeline at runtime
      page.execute_script(<<~JS)
        (() => {
          const previewEl = document.querySelector("[data-controller~='preview']")
          const controller = window.Stimulus.controllers.find(c => c.element === previewEl && c.identifier === "preview")
          if (!controller || !controller._pipeline) return

          controller._pipeline.register({
            name: "test-broken",
            type: "sync",
            selector: "strong",
            dependencies: [],
            limits: { maxElements: 50 },
            fallbackHTML: (el) => `<span class="renderer-test-fallback">${el.textContent}</span>`,
            process(el) { throw new Error("Intentional test failure") }
          })

          // Re-trigger render
          const cm = document.querySelector("[data-controller~='codemirror']")
          const cmCtrl = window.Stimulus.controllers.find(c => c.element === cm && c.identifier === "codemirror")
          controller.update(cmCtrl.getValue())
        })()
      JS

      expect(page).to have_css(".renderer-test-fallback", text: "negrito", wait: 5)
      expect(page).to have_css(".preview-prose h1", text: "Heading Normal")
      expect(page).to have_css(".preview-prose code", text: "codigo")
    end
  end

  describe "basic pipeline rendering" do
    it "renders markdown with code blocks and block markers through the pipeline" do
      note = create(:note)
      Notes::CheckpointService.call(
        note: note,
        content: "# Titulo\n\n```ruby\nputs 'hello'\n```\n\nParagrafo com bloco ^meu-bloco",
        author: user
      )

      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 10)
      trigger_preview

      expect(page).to have_css(".preview-prose h1", text: "Titulo", wait: 5)
      expect(page).to have_css(".preview-prose pre code.cm-code-block")
      expect(page).to have_css(".preview-prose [id='meu-bloco']")
    end
  end

  # ── EPIC-04.3: Media embeds ──────────────────────────────────────────────

  describe "media embeds" do
    it "converts video URL images to video elements" do
      note = create(:note)
      Notes::CheckpointService.call(
        note: note,
        content: "# Video\n\n![meu video](https://example.com/test.mp4)",
        author: user
      )

      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 10)
      trigger_preview

      expect(page).to have_css(".preview-prose h1", text: "Video", wait: 5)
      expect(page).to have_css(".preview-prose .media-container video[controls]")
    end

    it "converts audio URL images to audio elements" do
      note = create(:note)
      Notes::CheckpointService.call(
        note: note,
        content: "# Audio\n\n![meu audio](https://example.com/test.mp3)",
        author: user
      )

      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 10)
      trigger_preview

      expect(page).to have_css(".preview-prose h1", text: "Audio", wait: 5)
      expect(page).to have_css(".preview-prose .media-container audio[controls]")
    end

    it "converts PDF URL images to iframe elements" do
      note = create(:note)
      Notes::CheckpointService.call(
        note: note,
        content: "# PDF\n\n![documento](https://example.com/test.pdf)",
        author: user
      )

      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 10)
      trigger_preview

      expect(page).to have_css(".preview-prose h1", text: "PDF", wait: 5)
      expect(page).to have_css(".preview-prose .media-container iframe")
    end

    it "enhances regular images with lazy loading" do
      note = create(:note)
      Notes::CheckpointService.call(
        note: note,
        content: "# Imagem\n\n![foto](https://example.com/photo.png)",
        author: user
      )

      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 10)
      trigger_preview

      expect(page).to have_css(".preview-prose h1", text: "Imagem", wait: 5)
      expect(page).to have_css(".preview-prose img[loading='lazy']")
    end
  end
end
