require "rails_helper"

# Regression specs for editor page HTML structure.
# These catch bugs where JS controllers are not mounted in the DOM
# (which would cause preview/autosave to silently fail).
RSpec.describe "Editor HTML structure", type: :request do
  let(:user) { create(:user) }
  let(:note) { create(:note, :with_head_revision) }

  before { sign_in user }

  describe "GET /notes/:slug (editor page)" do
    before { get note_path(note.slug) }

    # ── Regression: autosave controller was not mounted in DOM ──
    it "mounts autosave controller on editor-root" do
      expect(response.body).to include('data-controller="note-shell editor autosave ai-review tts note-tags"')
    end

    it "passes draft and checkpoint URLs to autosave controller" do
      expect(response.body).to include("data-autosave-draft-url-value")
      expect(response.body).to include(draft_note_path(note.slug))
      expect(response.body).to include("data-autosave-checkpoint-url-value")
      expect(response.body).to include(checkpoint_note_path(note.slug))
    end

    it "sets 60s draft debounce and 3s local debounce on autosave controller" do
      expect(response.body).to include('data-autosave-draft-ms-value="60000"')
      expect(response.body).to include('data-autosave-local-ms-value="3000"')
    end

    # ── Regression: _getPreviewController() used querySelector on previewPaneTarget
    #    which looked for children, but previewPane ITSELF has data-controller="preview"
    it "preview pane element itself has data-controller=preview" do
      expect(response.body).to match(/id="preview-pane"[^>]*data-controller="preview"/)
        .or match(/data-controller="preview"[^>]*id="preview-pane"/)
    end

    it "preview pane is also the editor previewPane target" do
      expect(response.body).to include('data-editor-target="previewPane"')
    end

    # ── Editor pane: codemirror controller is on the pane itself ──
    it "editor pane has codemirror controller" do
      expect(response.body).to include('data-controller="codemirror')
    end

    it "editor pane is the editor editorPane target" do
      expect(response.body).to include('data-editor-target="editorPane"')
    end

    # ── Initial content is pre-loaded into CodeMirror ──
    it "passes initial content to codemirror controller" do
      expect(response.body).to include("data-codemirror-initial-value-value")
    end

    # ── Uses editor layout (no navbar) ──
    it "renders editor layout without the main navbar" do
      expect(response.body).not_to include('<nav class="border-b')
    end

    it "uses graph as the back destination" do
      expect(response.body).to include(graph_path)
      expect(response.body).to include("Voltar para o grafo")
    end

    it "renders full-screen editor root" do
      expect(response.body).to include('id="editor-root"')
    end

    it "renders the dynamic ai stream source inside the editor shell" do
      expect(response.body).to include('data-note-shell-target="streamSource"')
    end

    # ── Toolbar format buttons ──
    %w[bold italic strikethrough highlight inlineCode link].each do |action|
      it "has toolbar button for text-format##{action}" do
        expect(response.body).to include("click->text-format##{action}")
      end
    end

    %w[heading1 heading2 heading3 bulletList numberList blockquote codeBlock].each do |action|
      it "has toolbar button for text-format##{action}" do
        expect(response.body).to include("click->text-format##{action}")
      end
    end

    it "has toolbar button for table-editor#open" do
      expect(response.body).to include("click->table-editor#open")
    end

    it "renders table editor dialog" do
      expect(response.body).to include('data-controller="table-editor"')
      expect(response.body).to include('data-table-editor-target="dialog"')
      expect(response.body).to include('data-table-editor-target="grid"')
    end

    it "has toolbar button for emoji-picker#open" do
      expect(response.body).to include("click->emoji-picker#open")
    end

    it "renders emoji picker dialog" do
      expect(response.body).to include('data-controller="emoji-picker"')
      expect(response.body).to include('data-emoji-picker-target="dialog"')
      expect(response.body).to include('data-emoji-picker-target="grid"')
    end

    it "has theme picker with toggle and menu" do
      expect(response.body).to include('data-controller="theme"')
      expect(response.body).to include('data-theme-target="menu"')
      expect(response.body).to include("click->theme#toggle")
    end

    it "renders shortcuts help dialog with keyboard reference" do
      expect(response.body).to include('id="shortcuts-help-dialog"')
      expect(response.body).to include("Atalhos e Markdown")
      expect(response.body).to include("<kbd>Ctrl+B</kbd>")
      expect(response.body).to include("<kbd>F1</kbd>")
    end
  end
end
