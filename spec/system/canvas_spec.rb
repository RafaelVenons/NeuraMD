require "rails_helper"

RSpec.describe "Canvas", type: :system do
  let(:user) { create(:user) }

  before do
    login_as user, scope: :user
  end

  describe "index page" do
    it "shows existing canvas documents" do
      create(:canvas_document, name: "Neuro Canvas")
      visit canvas_documents_path

      expect(page).to have_text("Neuro Canvas")
      expect(page).to have_css(".cv-index__form")
    end

    it "shows empty state when no canvas exists" do
      visit canvas_documents_path
      expect(page).to have_text("Nenhum canvas criado")
    end
  end

  describe "navigation" do
    it "shows Canvas link in the nav bar" do
      visit canvas_documents_path
      expect(page).to have_link("Canvas", href: canvas_documents_path)
    end
  end

  describe "show page" do
    it "shows canvas viewport with toolbar" do
      doc = create(:canvas_document, name: "Test Canvas")

      visit canvas_document_path(doc)

      expect(page).to have_text("Test Canvas")
      expect(page).to have_css(".cv-toolbar")
      expect(page).to have_css(".cv-viewport")
    end

    it "renders nodes in the viewport" do
      doc = create(:canvas_document, name: "With Nodes")
      note = create(:note, title: "Neuroscience Basics")
      create(:canvas_node, :note_type, canvas_document: doc, note: note, x: 100, y: 100)
      create(:canvas_node, canvas_document: doc, node_type: "text", data: {"text" => "A text node"}, x: 300, y: 200)

      visit canvas_document_path(doc)

      expect(page).to have_css(".cv-toolbar", wait: 5)
      # Nodes are rendered by JS — check that the data attributes are present
      expect(page).to have_css("[data-canvas-initial-nodes-value]")
    end

    it "has toolbar buttons for tools" do
      doc = create(:canvas_document, name: "Toolbar Test")
      visit canvas_document_path(doc)

      expect(page).to have_css(".cv-tool-btn", minimum: 5)
      expect(page).to have_css(".cv-toolbar__zoom")
    end

    it "links back to canvas index" do
      doc = create(:canvas_document, name: "Back Link")
      visit canvas_document_path(doc)

      expect(page).to have_link(href: canvas_documents_path)
    end
  end

  describe "interaction" do
    it "renders note nodes from initial data" do
      doc = create(:canvas_document, name: "Render Test")
      note = create(:note, title: "Cortex Note")
      create(:canvas_node, :note_type, canvas_document: doc, note: note, x: 50, y: 80)

      visit canvas_document_path(doc)

      expect(page).to have_css(".cv-node--note", text: "Cortex Note", wait: 10)
    end

    it "renders text nodes from initial data" do
      doc = create(:canvas_document, name: "Text Test")
      create(:canvas_node, canvas_document: doc, node_type: "text", data: {"text" => "Hello Canvas"}, x: 200, y: 150)

      visit canvas_document_path(doc)

      expect(page).to have_css(".cv-node--text", text: "Hello Canvas", wait: 10)
    end

    it "renders edges between nodes" do
      doc = create(:canvas_document, name: "Edge Test")
      n1 = create(:canvas_node, canvas_document: doc, x: 50, y: 50)
      n2 = create(:canvas_node, canvas_document: doc, x: 300, y: 200)
      create(:canvas_edge, canvas_document: doc, source_node: n1, target_node: n2)

      visit canvas_document_path(doc)

      expect(page).to have_css(".cv-edge-path", wait: 10)
    end

    it "selects a node on click" do
      doc = create(:canvas_document, name: "Select Test")
      note = create(:note, title: "Selectable Note")
      create(:canvas_node, :note_type, canvas_document: doc, note: note, x: 100, y: 100)

      visit canvas_document_path(doc)

      node = find(".cv-node--note", text: "Selectable Note", wait: 10)
      node.click

      expect(node).to match_css(".cv-node--selected")
    end

    it "shows zoom percentage in toolbar" do
      doc = create(:canvas_document, name: "Zoom Test", viewport: {"x" => 0, "y" => 0, "zoom" => 1.0})

      visit canvas_document_path(doc)

      expect(page).to have_css(".cv-toolbar__zoom", text: "100%", wait: 5)
    end

    it "toolbar buttons switch active tool" do
      doc = create(:canvas_document, name: "Tool Switch")

      visit canvas_document_path(doc)

      # Find the pan button and click it
      pan_btn = find(".cv-tool-btn[data-canvas-toolbar-tool-param='pan']", wait: 5)
      pan_btn.click

      expect(pan_btn).to match_css(".is-active")
    end
  end
end
