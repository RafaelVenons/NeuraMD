require "rails_helper"

RSpec.describe "Render pipeline", type: :system do
  let(:user) { create(:user) }
  let!(:note) { create(:note) }

  before do
    login_as user, scope: :user
  end

  def editor
    find(".cm-content")
  end

  def preview_output
    find("[data-preview-target='output']")
  end

  # ── EPIC-04.1: Renderer contract ─────────────────────────────────────────

  describe "renderer isolation" do
    it "shows fallback when a renderer throws, without breaking other renderers" do
      Notes::CheckpointService.call(
        note: note,
        content: "# Heading Normal\n\nTexto com **negrito** e `codigo`.",
        author: user
      )

      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 5)

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

      # The broken renderer's fallback should appear
      expect(page).to have_css(".renderer-test-fallback", text: "negrito", wait: 5)

      # Other rendering still works — heading and code are present
      expect(page).to have_css(".preview-prose h1", text: "Heading Normal")
      expect(page).to have_css(".preview-prose code", text: "codigo")
    end
  end

  describe "basic pipeline rendering" do
    it "renders markdown with code blocks and block markers through the pipeline" do
      Notes::CheckpointService.call(
        note: note,
        content: "# Titulo\n\n```ruby\nputs 'hello'\n```\n\nParagrafo com bloco ^meu-bloco",
        author: user
      )

      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 5)

      # Wait for preview to render the heading (debounced at 150ms)
      expect(page).to have_css(".preview-prose h1", text: "Titulo", wait: 5)
      expect(page).to have_css(".preview-prose pre code.cm-code-block")
      # Block marker should be stripped and applied as element id
      expect(page).to have_css(".preview-prose [id='meu-bloco']")
    end
  end
end
