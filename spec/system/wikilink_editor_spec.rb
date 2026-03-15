require "rails_helper"

# Acceptance tests for wiki-link autocomplete dropdown and link-mode detection.
# Runs in real Chromium via Cuprite — exercises actual JS.
RSpec.describe "Wiki-link editor", type: :system do
  let(:user) { create(:user) }
  let!(:target) { create(:note, title: "Nota Destino") }
  let!(:alt_target) { create(:note, title: "Cardio Geral") }
  let!(:alt_target_two) { create(:note, title: "Cardiologia Avancada") }

  before do
    login_as user, scope: :user
    note = create(:note)
    visit note_path(note.slug)
    # Wait for CodeMirror to mount
    expect(page).to have_css(".cm-editor", wait: 5)
    expect(page).to have_css("[data-wikilink-ready='true']", wait: 5)
  end

  def editor
    find(".cm-content")
  end

  def type_in_editor(text)
    editor.click
    editor.send_keys(text)
  end

  def clear_editor
    editor.click
    page.execute_script("
      const view = document.querySelector('.cm-editor')._codemirror_view
        || window._cmView;
      // Use select-all + delete to clear
    ")
    editor.send_keys([:control, "a"], :backspace)
  end

  # ── Dropdown appears and is navigable ───────────────────────────────────

  describe "autocomplete dropdown" do
    it "opens when user types [[" do
      type_in_editor("[[")
      expect(page).to have_css(".wikilink-dropdown:not([hidden])", wait: 3)
    end

    it "filters suggestions by title as user continues typing" do
      type_in_editor("[[Nota")
      expect(page).to have_css(".wikilink-dropdown:not([hidden])", wait: 3)
      expect(page).to have_css(".wikilink-suggestion", wait: 3)
      expect(page).to have_text("Nota Destino")
    end

    it "orders suggestions by cosine similarity for fuzzy matches" do
      type_in_editor("[[cardio")
      expect(page).to have_css(".wikilink-suggestion", minimum: 2, wait: 3)

      labels = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll(".wikilink-suggestion")).map((el) => el.textContent.trim())
      JS

      expect(labels.first(2)).to eq(["Cardio Geral", "Cardiologia Avancada"])
    end

    it "does not suggest the current note itself" do
      current_note = Note.find_by!(slug: current_path.split("/").last)
      current_note.update!(title: "Nota Destino")

      visit note_path(current_note.slug)
      expect(page).to have_css(".cm-editor", wait: 5)

      type_in_editor("[[Nota")
      expect(page).to have_css(".wikilink-suggestion", wait: 3)
      labels = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll(".wikilink-suggestion")).map((el) => el.textContent.trim())
      JS

      expect(labels.count("Nota Destino")).to eq(1)
    end

    it "closes on Escape" do
      type_in_editor("[[")
      expect(page).to have_css(".wikilink-dropdown:not([hidden])", wait: 3)
      editor.send_keys(:escape)
      expect(page).not_to have_css(".wikilink-dropdown:not([hidden])", wait: 2)
    end

    it "lets user continue typing letters while dropdown is open" do
      type_in_editor("[[Not")
      expect(page).to have_css(".wikilink-dropdown:not([hidden])", wait: 3)

      # This was the regression: typing was blocked because dropdown stole focus
      type_in_editor("a")
      # Dropdown should still be open and show filtered results
      expect(page).to have_css(".wikilink-dropdown:not([hidden])", wait: 2)
      # Editor content should contain the typed characters
      expect(editor.text).to include("[[Nota")
    end

    it "navigates suggestions with arrow keys without moving editor cursor" do
      type_in_editor("[[Nota")
      expect(page).to have_css(".wikilink-suggestion", wait: 3)

      # Arrow down highlights first item
      editor.send_keys(:down)
      expect(page).to have_css(".wikilink-suggestion.active", wait: 1)
    end

    it "inserts wiki-link markup on Enter" do
      type_in_editor("[[Nota")
      expect(page).to have_css(".wikilink-suggestion", wait: 3)
      editor.send_keys(:enter)

      # Dropdown closes and markup is in the editor
      expect(page).not_to have_css(".wikilink-dropdown:not([hidden])", wait: 2)
      expect(editor.text).to match(/\[\[Nota Destino\|[0-9a-f-]{36}\]\]/)
    end

    it "inserts wiki-link on Tab" do
      type_in_editor("[[Nota")
      expect(page).to have_css(".wikilink-suggestion", wait: 3)
      editor.send_keys(:tab)
      expect(editor.text).to match(/\[\[Nota Destino\|[0-9a-f-]{36}\]\]/)
    end

    it "renders broken wikilinks as animated red text without showing raw markup" do
      type_in_editor("[[Quebrado|00000000-0000-0000-0000-000000000000]]")

      within(".preview-prose") do
        expect(page).to have_css(".wikilink-broken", text: "Quebrado", wait: 5)
        expect(page).to have_no_css("a[href='/notes/00000000-0000-0000-0000-000000000000']", wait: 5)
        expect(page).to have_no_text("[[Quebrado|00000000-0000-0000-0000-000000000000]]")
      end
    end

    it "renders non-uuid wikilink targets as broken text in preview" do
      type_in_editor("[[Quebrado|nao-e-uuid]]")

      within(".preview-prose") do
        expect(page).to have_css(".wikilink-broken", text: "Quebrado", wait: 5)
        expect(page).to have_no_css("a.wikilink", wait: 2)
        expect(page).to have_no_text("[[Quebrado|nao-e-uuid]]")
      end
    end

    it "does not open wikilink autocomplete while IME composition is active" do
      page.execute_script(<<~JS)
        const content = document.querySelector(".cm-content")
        content.dispatchEvent(new CompositionEvent("compositionstart", { bubbles: true, data: "に" }))
      JS

      type_in_editor("[[")
      expect(page).to have_no_css(".wikilink-dropdown:not([hidden])", wait: 1)
    end

    it "cycles hier_role with Left/Right arrows" do
      type_in_editor("[[")
      expect(page).to have_css(".wikilink-dropdown:not([hidden])", wait: 3)

      expect(page).to have_css(".wikilink-role-current", text: "Ref", wait: 1)
      editor.send_keys(:right)
      expect(page).to have_css(".wikilink-role-current", text: "Father", wait: 1)
      editor.send_keys(:right)
      expect(page).to have_css(".wikilink-role-current", text: "Child", wait: 1)
      editor.send_keys(:right)
      expect(page).to have_css(".wikilink-role-current", text: "Brother", wait: 1)
      editor.send_keys(:left)
      expect(page).to have_css(".wikilink-role-current", text: "Child", wait: 1)
    end
  end

  # ── Link mode detection ─────────────────────────────────────────────────

  describe "tag sidebar link mode" do
    let!(:inserted_note) { create(:note, title: "Alvo") }

    it "shows Global mode by default" do
      expect(page).to have_css("[data-tag-sidebar-target='modeLabel']", text: /global/i, wait: 3)
    end

    it "switches to Link mode when cursor enters a wiki-link" do
      # Insert a complete wiki-link via the dropdown
      type_in_editor("[[Alvo")
      expect(page).to have_css(".wikilink-suggestion", wait: 3)
      editor.send_keys(:enter)

      # Move cursor to position 0 (inside the link, since the note starts with [[)
      editor.send_keys([:control, :home])

      # Sidebar should now show Link mode
      expect(page).to have_css("[data-tag-sidebar-target='modeLabel']", text: /link/i, wait: 3)
    end

    it "returns to Global mode when cursor leaves the wiki-link" do
      type_in_editor("[[Alvo")
      expect(page).to have_css(".wikilink-suggestion", wait: 3)
      editor.send_keys(:enter)

      # Move inside link
      editor.send_keys([:control, :home])
      expect(page).to have_css("[data-tag-sidebar-target='modeLabel']", text: /link/i, wait: 3)

      # Move to end (past the link) and type a space
      editor.send_keys([:control, :end], " ")
      expect(page).to have_css("[data-tag-sidebar-target='modeLabel']", text: /global/i, wait: 3)
    end

    it "is in Link mode for every cursor position when entire note is one wiki-link" do
      type_in_editor("[[Alvo")
      expect(page).to have_css(".wikilink-suggestion", wait: 3)
      editor.send_keys(:enter)

      # Cursor is right after ]] — still within bounds (<=)
      expect(page).to have_css("[data-tag-sidebar-target='modeLabel']", text: /link/i, wait: 3)

      # Move to beginning — still link mode
      editor.send_keys([:control, :home])
      expect(page).to have_css("[data-tag-sidebar-target='modeLabel']", text: /link/i, wait: 3)
    end
  end
end
