require "rails_helper"

# Acceptance tests for the tag sidebar UI.
# Covers: layout, dot sizes, new-tag creation flows, and link-mode tag toggling.
RSpec.describe "Tag sidebar", type: :system do
  let(:user) { create(:user) }
  let!(:note) { create(:note) }

  before do
    login_as user, scope: :user
    visit note_path(note.slug)
    expect(page).to have_css(".cm-editor", wait: 5)
  end

  # ── Layout ──────────────────────────────────────────────────────────────

  describe "new-tag row position" do
    it "appears inside the scrollable tag list (not as a fixed footer)" do
      expect(page).to have_css(".tag-list .tag-new-row", wait: 3)
    end

    it "sticks to the bottom of the list when scrolling is needed" do
      sticky = page.evaluate_script(<<~JS)
        (() => {
          const row = document.querySelector(".tag-new-row")
          const styles = getComputedStyle(row)
          return { position: styles.position, bottom: styles.bottom }
        })()
      JS

      expect(sticky["position"]).to eq("sticky")
      expect(sticky["bottom"]).to eq("0px")
    end

    it "appears after all tag items in the list" do
      create_list(:tag, 3)
      visit current_path
      expect(page).to have_css(".cm-editor", wait: 5)
      expect(page).to have_css(".tag-item", wait: 3)

      positions = page.evaluate_script(<<~JS)
        (() => {
          const items = Array.from(document.querySelectorAll(".tag-list > *"))
          const lastTagIdx = items.reduce((acc, el, i) => el.classList.contains("tag-item") ? i : acc, -1)
          const newRowIdx  = items.findIndex(el => el.classList.contains("tag-new-row"))
          return { lastTagIdx, newRowIdx }
        })()
      JS

      expect(positions["newRowIdx"]).to be > positions["lastTagIdx"]
    end
  end

  describe "dot size" do
    it "renders tag dots with size >= 22px" do
      create(:tag)
      visit current_path
      expect(page).to have_css(".cm-editor", wait: 5)
      expect(page).to have_css(".tag-dot-svg", wait: 3)

      width = page.evaluate_script(
        'document.querySelector(".tag-dot-svg")?.getAttribute("width")'
      ).to_i
      expect(width).to be >= 22
    end

    it "renders the new-tag dot at the same size as tag dots" do
      create(:tag)
      visit current_path
      expect(page).to have_css(".cm-editor", wait: 5)
      expect(page).to have_css(".tag-item .tag-dot-svg", wait: 3)

      tag_width = page.evaluate_script(
        'document.querySelector(".tag-item .tag-dot-svg")?.getAttribute("width")'
      ).to_i
      new_dot_width = page.evaluate_script(
        'document.querySelector(".tag-new-dot-btn svg")?.getAttribute("width")'
      ).to_i

      expect(new_dot_width).to be > 0
      expect(new_dot_width).to eq(tag_width)
    end

    it "keeps the dot aligned when collapsing the sidebar" do
      create(:tag, name: "alpha")
      visit current_path
      expect(page).to have_css(".tag-item .tag-dot-svg", wait: 3)

      positions = page.evaluate_script(<<~JS)
        (() => {
          const toggle = document.querySelector(".tag-sidebar-toggle-btn")
          const dot = document.querySelector(".tag-item .tag-dot-svg")
          const before = dot.getBoundingClientRect().left
          toggle.click()
          const after = dot.getBoundingClientRect().left
          return { before, after, delta: Math.abs(before - after) }
        })()
      JS

      expect(positions["delta"]).to be <= 2
    end
  end

  describe "global mode ordering" do
    let!(:tag_most_used) { create(:tag, name: "Mais usada") }
    let!(:tag_less_used) { create(:tag, name: "Menos usada") }
    let!(:tag_unused)    { create(:tag, name: "Nao usada") }
    let!(:note_with_links) do
      dst1 = create(:note, title: "Destino 1")
      dst2 = create(:note, title: "Destino 2")
      dst3 = create(:note, title: "Destino 3")

      n = create(:note)
      Notes::CheckpointService.call(
        note: n,
        content: "[[Destino 1|#{dst1.id}]] [[Destino 2|#{dst2.id}]] [[Destino 3|#{dst3.id}]]",
        author: user
      )

      links = n.outgoing_links.order(:created_at).to_a
      LinkTag.create!(note_link: links[0], tag: tag_most_used)
      LinkTag.create!(note_link: links[1], tag: tag_most_used)
      LinkTag.create!(note_link: links[2], tag: tag_less_used)
      n
    end

    it "orders tags by in-note usage descending" do
      visit note_path(note_with_links.slug)
      expect(page).to have_css(".cm-editor", wait: 5)
      expect(page).to have_css(".tag-item", minimum: 3, wait: 3)

      names = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll(".tag-item .tag-name")).map((el) => el.textContent.trim())
      JS

      expect(names.first(3)).to eq(["mais usada", "menos usada", "nao usada"])
    end
  end

  # ── New tag creation flows ───────────────────────────────────────────────

  describe "creating a new tag" do
    def name_input
      find("[data-tag-sidebar-target='nameInput']")
    end

    def open_color_picker
      find("[data-tag-sidebar-target='newDotBtn']").click
      expect(page).to have_css(".tag-color-picker:not([hidden])", wait: 3)
    end

    def pick_first_suggestion
      find(".tcp-swatch", match: :first, wait: 3).click
    end

    def trigger_color_change(hex = "#e11d48")
      open_color_picker
      pick_first_suggestion
    end

    it "creates the tag automatically when name is typed before color is confirmed" do
      name_input.fill_in with: "urgente"
      trigger_color_change("#e11d48")

      expect(page).to have_css(".tag-item", text: "urgente", wait: 3)
      expect(page).to have_css(".tag-item", text: "urgente", count: 1)
    end

    it "focuses the name input when color is confirmed without a name" do
      trigger_color_change("#16a34a")

      focused = page.evaluate_script(
        "document.activeElement === document.querySelector(\"[data-tag-sidebar-target='nameInput']\")"
      )
      expect(focused).to be true
    end

    it "creates the tag when Enter is pressed in the name input" do
      name_input.fill_in with: "revisao"
      name_input.send_keys(:enter)

      expect(page).to have_css(".tag-item", text: "revisao", wait: 3)
    end

    it "opens a custom color picker popup when dot is clicked" do
      find("[data-tag-sidebar-target='newDotBtn']").click
      expect(page).to have_css(".tag-color-picker:not([hidden])", wait: 3)
      expect(page).to have_css(".tcp-swatch", wait: 2)
    end

    it "closes the picker when clicking outside without selecting" do
      find("[data-tag-sidebar-target='newDotBtn']").click
      expect(page).to have_css(".tag-color-picker:not([hidden])", wait: 3)
      # Click outside the picker (on the mode label area)
      find("[data-tag-sidebar-target='modeLabel']").click
      expect(page).not_to have_css(".tag-color-picker:not([hidden])", wait: 2)
    end

    it "shows harmony suggestions and the chromatic wheel" do
      find("[data-tag-sidebar-target='newDotBtn']").click
      expect(page).to have_css(".tag-color-picker:not([hidden])", wait: 3)
      expect(page).to have_css(".tcp-swatches .tcp-swatch", minimum: 6, wait: 2)
      expect(page).to have_css(".tcp-wheel-canvas", wait: 2)
      expect(page).to have_css(".tcp-wcag", wait: 2)
    end

    it "shows no visible divider line between tags and new-tag row" do
      border = page.evaluate_script(
        "getComputedStyle(document.querySelector('.tag-new-row')).borderTopWidth"
      )
      expect(border).to eq("0px")
    end

    it "clears the name input after tag creation" do
      name_input.fill_in with: "limpar"
      name_input.send_keys(:enter)

      expect(page).to have_css(".tag-item", text: "limpar", wait: 3)
      expect(name_input.value).to eq("")
    end

    it "reuses an existing tag instead of failing silently on duplicate names" do
      create(:tag, name: "duplicada")
      visit current_path
      expect(page).to have_css(".cm-editor", wait: 5)

      name_input.fill_in with: "Duplicada"
      name_input.send_keys(:enter)

      expect(page).to have_css(".tag-item", text: "duplicada", count: 1, wait: 3)
      expect(name_input.value).to eq("")
    end

    it "suggests a next color far from the dominant hues in the note" do
      dominant = create(:tag, name: "Dominante", color_hex: "#ef4444")
      secondary = create(:tag, name: "Secundaria", color_hex: "#f97316")

      dst1 = create(:note, title: "Destino 1")
      dst2 = create(:note, title: "Destino 2")
      dst3 = create(:note, title: "Destino 3")

      weighted_note = create(:note)
      Notes::CheckpointService.call(
        note: weighted_note,
        content: "[[Destino 1|#{dst1.id}]] [[Destino 2|#{dst2.id}]] [[Destino 3|#{dst3.id}]]",
        author: user
      )

      links = weighted_note.outgoing_links.order(:created_at).to_a
      LinkTag.create!(note_link: links[0], tag: dominant)
      LinkTag.create!(note_link: links[1], tag: dominant)
      LinkTag.create!(note_link: links[2], tag: secondary)

      visit note_path(weighted_note.slug)
      expect(page).to have_css(".cm-editor", wait: 5)

      distance = page.evaluate_script(<<~JS)
        (() => {
          const hexToHue = (hex) => {
            const rgb = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
            const max = Math.max(...rgb)
            const min = Math.min(...rgb)
            if (max === min) return 0
            const d = max - min
            let h = 0
            if (max === rgb[0]) h = ((rgb[1] - rgb[2]) / d + (rgb[1] < rgb[2] ? 6 : 0))
            else if (max === rgb[1]) h = ((rgb[2] - rgb[0]) / d + 2)
            else h = ((rgb[0] - rgb[1]) / d + 4)
            return Math.round((h / 6) * 360)
          }

          const angularDistance = (a, b) => {
            const diff = Math.abs(a - b) % 360
            return Math.min(diff, 360 - diff)
          }

          const dominantColor = document.querySelector(".tag-item .tag-dot-svg circle")?.getAttribute("fill")
          const newColor = document.querySelector(".tag-new-dot-btn svg circle")?.getAttribute("fill")
          return angularDistance(hexToHue(dominantColor), hexToHue(newColor))
        })()
      JS

      expect(distance).to be >= 120
    end

    it "does not show a submit button next to the name input" do
      expect(page).not_to have_css(".tag-new-submit")
    end
  end

  # ── Link mode — tag toggling ─────────────────────────────────────────────
  #
  # Regression guard: clicking a tag in link mode must add/remove it on the link.
  # When the link only exists in the latest draft, the sidebar should persist the
  # draft first and then complete the toggle without requiring a manual checkpoint.

  describe "link mode tag toggling" do
    let!(:dst_note) { create(:note, title: "Destino") }
    let!(:tag)      { create(:tag, color_hex: "#ef4444") }

    # A note that has been checkpointed with a wiki-link so note_link exists in DB.
    let!(:src_note) do
      n = create(:note)
      Notes::CheckpointService.call(
        note: n,
        content: "[[Destino|#{dst_note.id}]]",
        author: user
      )
      n
    end

    def place_cursor_in_link
      # Move cursor to the very beginning of the document; the wiki-link starts there.
      find(".cm-content").click
      find(".cm-content").send_keys([:control, :home])
    end

    context "when the link exists in the database (checkpoint saved)" do
      before do
        visit note_path(src_note.slug)
        expect(page).to have_css(".cm-editor", wait: 5)
      end

      it "transitions the sidebar to Link mode when cursor enters the wiki-link" do
        place_cursor_in_link
        expect(page).to have_css("[data-tag-sidebar-target='modeLabel']", text: /link/i, wait: 4)
      end

      it "renders tags as checkboxes with toggleLinkTag action" do
        place_cursor_in_link
        expect(page).to have_css("[data-tag-sidebar-target='modeLabel']", text: /link/i, wait: 4)
        expect(page).to have_css(".tag-item[data-action*='toggleLinkTag']", wait: 3)
      end

      it "adds a tag to the link when clicked and marks it as active" do
        place_cursor_in_link
        # Wait for sidebar to load link_id (notice must disappear first)
        expect(page).to have_css("[data-tag-sidebar-target='modeLabel']", text: /link/i, wait: 4)
        expect(page).not_to have_css(".tag-link-notice", wait: 4)

        find(".tag-item", text: tag.name, wait: 3).click

        # JS re-renders the tag as checked; wait for it
        expect(page).to have_css(".tag-item--active", wait: 3)

        # Verify DB: the link now has the tag associated
        link = src_note.outgoing_links.find_by(dst_note_id: dst_note.id)
        expect(link.reload.tags).to include(tag)
      end

      it "removes a tag from the link when clicked a second time" do
        # Pre-associate the tag so we can then remove it
        link = src_note.outgoing_links.find_by(dst_note_id: dst_note.id)
        LinkTag.create!(note_link_id: link.id, tag_id: tag.id)

        visit note_path(src_note.slug)
        expect(page).to have_css(".cm-editor", wait: 5)

        place_cursor_in_link
        expect(page).to have_css("[data-tag-sidebar-target='modeLabel']", text: /link/i, wait: 4)
        expect(page).not_to have_css(".tag-link-notice", wait: 4)

        # Tag should appear as active (already linked)
        expect(page).to have_css(".tag-item--active", wait: 3)

        # Click to remove
        find(".tag-item--active", wait: 3).click
        expect(page).not_to have_css(".tag-item--active", wait: 3)

        expect(link.reload.tags).not_to include(tag)
      end
    end

    context "when the link has not been checkpointed yet" do
      let!(:fresh_note) { create(:note) }

      before do
        visit note_path(fresh_note.slug)
        expect(page).to have_css(".cm-editor", wait: 5)

        # Type a wiki-link into the editor — no checkpoint, so no note_link in DB
        find(".cm-content").click
        find(".cm-content").send_keys("[[Destino|#{dst_note.id}]]")
        find(".cm-content").send_keys([:control, :home])
      end

      it "does not show a checkpoint notice in link mode" do
        expect(page).to have_css("[data-tag-sidebar-target='modeLabel']", text: /link/i, wait: 4)
        expect(page).not_to have_css(".tag-link-notice", wait: 2)
      end

      it "allows tagging by saving the latest draft first" do
        expect(page).to have_css("[data-tag-sidebar-target='modeLabel']", text: /link/i, wait: 4)
        find(".tag-item", text: tag.name, wait: 3).click

        expect(page).to have_css(".tag-item--active", wait: 4)

        link = fresh_note.outgoing_links.find_by(dst_note_id: dst_note.id)
        expect(link).to be_present
        expect(link.tags).to include(tag)
        expect(fresh_note.note_revisions.where(revision_kind: :draft)).to exist
      end

      it "creates and immediately associates a new tag to the focused link" do
        expect(page).to have_css("[data-tag-sidebar-target='modeLabel']", text: /link/i, wait: 4)

        find("[data-tag-sidebar-target='nameInput']").fill_in with: "nova-tag-link"
        find("[data-tag-sidebar-target='nameInput']").send_keys(:enter)

        expect(page).to have_css(".tag-item--active", text: "nova-tag-link", wait: 4)

        created_tag = Tag.find_by!(name: "nova-tag-link")
        link = fresh_note.outgoing_links.find_by(dst_note_id: dst_note.id)
        expect(link).to be_present
        expect(link.tags).to include(created_tag)
      end

      it "reuses and associates an existing tag when the same name is entered" do
        existing_tag = create(:tag, name: "reaproveitar", color_hex: "#10b981")
        visit note_path(fresh_note.slug)
        expect(page).to have_css(".cm-editor", wait: 5)

        find(".cm-content").click
        find(".cm-content").send_keys("[[Destino|#{dst_note.id}]]")
        find(".cm-content").send_keys([:control, :home])
        expect(page).to have_css("[data-tag-sidebar-target='modeLabel']", text: /link/i, wait: 4)

        find("[data-tag-sidebar-target='nameInput']").fill_in with: "Reaproveitar"
        find("[data-tag-sidebar-target='nameInput']").send_keys(:enter)

        expect(page).to have_css(".tag-item--active", text: "reaproveitar", wait: 4)

        link = fresh_note.outgoing_links.find_by(dst_note_id: dst_note.id)
        expect(link).to be_present
        expect(link.tags).to include(existing_tag)
      end

      context "when there are no existing tags yet" do
        before do
          Tag.delete_all
          visit note_path(fresh_note.slug)
          expect(page).to have_css(".cm-editor", wait: 5)

          find(".cm-content").click
          find(".cm-content").send_keys("[[Destino|#{dst_note.id}]]")
          find(".cm-content").send_keys([:control, :home])
          expect(page).to have_css("[data-tag-sidebar-target='modeLabel']", text: /link/i, wait: 4)
          expect(page).not_to have_css(".tag-item", wait: 2)
        end

        it "creates the first tag and associates it to the new link" do
          find("[data-tag-sidebar-target='nameInput']").fill_in with: "primeira-tag"
          find("[data-tag-sidebar-target='nameInput']").send_keys(:enter)

          expect(page).to have_css(".tag-item--active", text: "primeira-tag", wait: 4)

          created_tag = Tag.find_by!(name: "primeira-tag")
          link = fresh_note.outgoing_links.find_by(dst_note_id: dst_note.id)
          expect(link).to be_present
          expect(link.tags).to include(created_tag)
        end
      end
    end
  end
end
