require "rails_helper"

RSpec.describe "Properties panel in editor", type: :system do
  let(:user) { create(:user) }
  let!(:note) { create(:note, :with_head_revision) }
  let!(:status_def) { create(:property_definition, key: "status", value_type: "enum", label: "Status", config: {"options" => %w[draft review published]}, position: 0) }
  let!(:priority_def) { create(:property_definition, key: "priority", value_type: "number", label: "Prioridade", position: 1) }

  before do
    login_as user, scope: :user
    visit note_path(note.slug)
    expect(page).to have_css(".cm-editor", wait: 5)
    # Clear localStorage to ensure consistent initial state
    page.execute_script("localStorage.removeItem('editor-layout-state')")
    visit note_path(note.slug)
    expect(page).to have_css(".cm-editor", wait: 5)
  end

  describe "toggling the panel" do
    it "opens the properties panel when clicking the toolbar button" do
      expect(page).to have_css("#properties-panel.hidden", visible: :all)

      find("[data-editor-target='propertiesToggleBtn']").click
      expect(page).to have_no_css("#properties-panel.hidden", visible: :all, wait: 2)
      expect(page).to have_css(".properties-panel-header", wait: 2)
    end

    it "shows empty state when no properties are set" do
      find("[data-editor-target='propertiesToggleBtn']").click
      expect(page).to have_text("Nenhuma propriedade definida", wait: 3)
    end
  end

  describe "adding a property" do
    before do
      find("[data-editor-target='propertiesToggleBtn']").click
      expect(page).to have_css(".properties-panel-footer", wait: 2)
    end

    it "shows available definitions in the add dropdown" do
      find("[data-properties-panel-target='addButton']").click
      expect(page).to have_css(".properties-add-option", text: "Status", wait: 3)
      expect(page).to have_css(".properties-add-option", text: "Prioridade", wait: 3)
    end

    it "adds a property and shows it in the list" do
      find("[data-properties-panel-target='addButton']").click
      find(".properties-add-option", text: "Status").click

      expect(page).to have_css(".properties-row", wait: 5)
      expect(page).to have_css(".properties-row-label", text: "Status", wait: 3)
    end
  end

  describe "editing a property" do
    before do
      Properties::SetService.call(note: note, changes: {"status" => "draft"}, author: user)
      note.reload
      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 5)
      find("[data-editor-target='propertiesToggleBtn']").click
      expect(page).to have_css(".properties-row", wait: 3)
    end

    it "shows the current value in the input" do
      within(".properties-row") do
        expect(page).to have_select(selected: "draft")
      end
    end

    it "saves on change and updates the UI" do
      within(".properties-row") do
        select "published", from: nil
      end

      # Wait for async save to complete
      sleep 1

      # Value persisted — reload to confirm (panel stays open via localStorage)
      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 5)
      expect(page).to have_css(".properties-row", wait: 5)

      within(".properties-row") do
        expect(page).to have_select(selected: "published", wait: 3)
      end
    end
  end

  describe "removing a property" do
    before do
      Properties::SetService.call(note: note, changes: {"status" => "draft"}, author: user)
      note.reload
      visit note_path(note.slug)
      expect(page).to have_css(".cm-editor", wait: 5)
      find("[data-editor-target='propertiesToggleBtn']").click
      expect(page).to have_css(".properties-row", wait: 3)
    end

    it "removes the property when clicking the x button" do
      within(".properties-row") do
        find(".properties-row-remove").click
      end

      expect(page).to have_text("Nenhuma propriedade definida", wait: 3)
    end
  end
end
