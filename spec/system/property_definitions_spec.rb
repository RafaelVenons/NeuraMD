require "rails_helper"

RSpec.describe "Property definitions settings", type: :system do
  let(:user) { create(:user) }

  before do
    login_as user, scope: :user
  end

  describe "viewing definitions" do
    it "shows existing definitions" do
      create(:property_definition, key: "status", value_type: "enum", label: "Status",
        config: {"options" => %w[draft review published]})
      create(:property_definition, key: "priority", value_type: "number", label: "Prioridade")

      visit property_definitions_path
      expect(page).to have_text("Status")
      expect(page).to have_text("Prioridade")
      expect(page).to have_text("enum")
      expect(page).to have_text("number")
    end

    it "shows archived definitions with visual indicator" do
      create(:property_definition, :archived, key: "old_field", value_type: "text", label: "Campo Antigo")

      visit property_definitions_path
      expect(page).to have_css(".propdef-row--archived", text: "Campo Antigo")
    end
  end

  describe "creating a definition" do
    before { visit property_definitions_path }

    it "creates a text definition" do
      within(".propdef-create") do
        find("[data-property-definitions-target='createKey']").set("author")
        find("[data-property-definitions-target='createType']").select("text")
        find("[data-property-definitions-target='createLabel']").set("Autor")
        click_button "Criar Definição"
      end

      expect(page).to have_text("Autor", wait: 3)
      expect(page).to have_text("author")
    end

    it "creates an enum definition with options" do
      within(".propdef-create") do
        find("[data-property-definitions-target='createKey']").set("status")
        find("[data-property-definitions-target='createType']").select("enum")
        find("[data-property-definitions-target='createLabel']").set("Status")
      end

      expect(page).to have_css(".propdef-config-options", wait: 2)
      find(".propdef-config-options").set("draft\nreview\npublished")

      within(".propdef-create") do
        click_button "Criar Definição"
      end

      expect(page).to have_text("Status", wait: 3)
      expect(page).to have_text("draft, review, published")
    end

    it "shows error for invalid key" do
      within(".propdef-create") do
        find("[data-property-definitions-target='createKey']").set("title")
        find("[data-property-definitions-target='createType']").select("text")
        click_button "Criar Definição"
      end

      expect(page).to have_css(".propdef-error-text", wait: 3)
    end
  end

  describe "archiving a definition" do
    it "removes the definition from the list" do
      create(:property_definition, key: "temp", value_type: "text", label: "Temporário")
      visit property_definitions_path

      accept_confirm do
        find(".propdef-row", text: "Temporário").find(".propdef-btn--danger").click
      end

      expect(page).to have_no_css(".propdef-row", text: "Temporário", wait: 3)
    end
  end
end
