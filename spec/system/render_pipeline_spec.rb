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

  # ── EPIC-04.4: Specialized renderers ─────────────────────────────────────

  describe "math rendering" do
    it "tokenizes inline math as math-inline span with data-math attribute" do
      note = create(:note)
      Notes::CheckpointService.call(
        note: note,
        content: "# Math\n\nA formula $E=mc^2$ inline.",
        author: user
      )

      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 10)
      trigger_preview

      expect(page).to have_css(".preview-prose h1", text: "Math", wait: 5)
      expect(page).to have_css(".preview-prose .math-inline[data-math]")
    end

    it "tokenizes display math as math-block div with data-math attribute" do
      note = create(:note)
      Notes::CheckpointService.call(
        note: note,
        content: "# Display\n\n$$\n\\int_0^1 x\\,dx\n$$",
        author: user
      )

      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 10)
      trigger_preview

      expect(page).to have_css(".preview-prose h1", text: "Display", wait: 5)
      expect(page).to have_css(".preview-prose .math-block[data-math]")
    end
  end

  describe "mermaid rendering" do
    it "renders mermaid code blocks as diagrams or shows graceful fallback" do
      note = create(:note)
      Notes::CheckpointService.call(
        note: note,
        content: "# Diagrama\n\n```mermaid\ngraph TD\n  A --> B\n```",
        author: user
      )

      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 10)
      trigger_preview

      expect(page).to have_css(".preview-prose h1", text: "Diagrama", wait: 5)
      # Either rendered as SVG container or graceful fallback (if CDN unreachable)
      has_mermaid = page.has_css?(".preview-prose .mermaid-container", wait: 10)
      has_fallback = page.has_css?(".preview-prose .renderer-fallback", wait: 1)
      expect(has_mermaid || has_fallback).to be true
    end
  end

  describe "specialized renderer isolation" do
    it "does not break the preview when a specialized renderer fails" do
      note = create(:note)
      Notes::CheckpointService.call(
        note: note,
        content: "# Mixed\n\nNormal text.\n\n```mermaid\ninvalid{{{syntax\n```\n\nMore text after.",
        author: user
      )

      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 10)
      trigger_preview

      expect(page).to have_css(".preview-prose h1", text: "Mixed", wait: 5)
      # Normal text should still render even if mermaid fails
      expect(page).to have_text("Normal text.")
      expect(page).to have_text("More text after.")
    end
  end

  # ── EPIC-04.5: Render budget protections ─────────────────────────────────

  describe "render budget protections" do
    it "shows budget warning when timeout guard fires and stops pipeline" do
      note = create(:note)
      Notes::CheckpointService.call(
        note: note,
        content: "# Budget\n\nNormal content.",
        author: user
      )

      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 10)
      trigger_preview
      expect(page).to have_css(".preview-prose h1", text: "Budget", wait: 5)

      # Inject a slow renderer and set a very low timeout to trigger the guard
      page.execute_script(<<~JS)
        (() => {
          const previewEl = document.querySelector("[data-controller~='preview']")
          const ctrl = window.Stimulus.controllers.find(c => c.element === previewEl && c.identifier === "preview")
          if (!ctrl || !ctrl._guards) return

          // Set absurdly low timeout
          ctrl._guards.maxRenderTimeMs = 0

          // Register a renderer that will be checked after the timeout
          ctrl._pipeline.register({
            name: "test-slow",
            type: "async",
            selector: "p",
            dependencies: [],
            limits: { maxElements: 100 },
            fallbackHTML: (el) => el.outerHTML,
            async processBatch(elements, context) {
              // This renderer just exists to trigger the timeout check
              await new Promise(r => setTimeout(r, 10))
            }
          })

          // Re-trigger render
          const cm = document.querySelector("[data-controller~='codemirror']")
          const cmCtrl = window.Stimulus.controllers.find(c => c.element === cm && c.identifier === "codemirror")
          ctrl.update(cmCtrl.getValue())
        })()
      JS

      expect(page).to have_css(".render-budget-warning", wait: 5)
      expect(page).to have_text("Preview truncado")
    end

    it "does not show budget warning for normal content" do
      note = create(:note)
      Notes::CheckpointService.call(
        note: note,
        content: "# Normal\n\nJust some text.\n\n- Item 1\n- Item 2",
        author: user
      )

      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 10)
      trigger_preview

      expect(page).to have_css(".preview-prose h1", text: "Normal", wait: 5)
      expect(page).not_to have_css(".render-budget-warning")
    end
  end
end
