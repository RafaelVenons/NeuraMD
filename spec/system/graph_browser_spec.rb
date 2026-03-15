require "rails_helper"

RSpec.describe "Graph browser", type: :system do
  let(:user) { create(:user) }

  before do
    login_as user, scope: :user
  end

  it "renders the graph with sigma, supports hover/click, and centers focus" do
    notes = Array.new(6) do |index|
      note = create(:note, title: "Node #{index + 1}")
      revision = create(:note_revision, note:, content_markdown: "Resumo #{index + 1} para o grafo")
      note.update_columns(head_revision_id: revision.id)
      note
    end

    high = create(:tag, name: "alta-prioridade", color_hex: "#ff6b35", tag_scope: "both")
    low = create(:tag, name: "baixa-prioridade", color_hex: "#3ba99c", tag_scope: "both")
    NoteTag.create!(note: notes.first, tag: high)
    NoteTag.create!(note: notes.second, tag: low)

    create(:note_link, src_note: notes.first, dst_note: notes.second, created_in_revision: notes.first.head_revision, hier_role: "target_is_parent")
    create(:note_link, src_note: notes.second, dst_note: notes.third, created_in_revision: notes.second.head_revision, hier_role: "target_is_child")
    create(:note_link, src_note: notes.third, dst_note: notes.fourth, created_in_revision: notes.third.head_revision, hier_role: "same_level")
    create(:note_link, src_note: notes.fourth, dst_note: notes.fifth, created_in_revision: notes.fourth.head_revision, hier_role: nil)
    create(:note_link, src_note: notes[4], dst_note: notes[5], created_in_revision: notes[4].head_revision, hier_role: "target_is_parent")

    visit graph_path

    expect(page).to have_css("[data-controller='graph']", wait: 10)
    expect(page).to have_css(".sigma-mouse", wait: 10)
    expect(page).to have_text("WebGL ativo", wait: 10)

    graph_stats = page.evaluate_script(<<~JS)
      (() => {
        const controller = window.__graphDebug
        return {
          nodes: controller.state.graph.order,
          edges: controller.state.graph.size,
          displayNodes: Array.from(controller.state.display.nodes.values()).filter((n) => !n.hidden).length,
          displayEdges: Array.from(controller.state.display.edges.values()).filter((e) => !e.hidden).length
        }
      })()
    JS

    expect(graph_stats).to include("nodes" => 6, "edges" => 5)
    expect(graph_stats["displayNodes"]).to be >= 5
    expect(graph_stats["displayEdges"]).to be >= 4

    page.execute_script(<<~JS, notes.first.id)
      const nodeId = arguments[0]
      const controller = window.__graphDebug
      const renderer = controller.state.renderer
      const display = renderer.getNodeDisplayData(nodeId)
      const point = renderer.graphToViewport({x: display.x, y: display.y})
      const target = document.querySelector(".sigma-mouse")
      const rect = target.getBoundingClientRect()
      const options = {bubbles: true, clientX: rect.left + point.x, clientY: rect.top + point.y}
      target.dispatchEvent(new MouseEvent("mousemove", options))
    JS

    expect(page).to have_css(".nm-graph-tooltip", text: notes.first.title, wait: 5)

    page.execute_script(<<~JS, notes.first.id)
      const nodeId = arguments[0]
      const controller = window.__graphDebug
      const renderer = controller.state.renderer
      const display = renderer.getNodeDisplayData(nodeId)
      const point = renderer.graphToViewport({x: display.x, y: display.y})
      const target = document.querySelector(".sigma-mouse")
      const rect = target.getBoundingClientRect()
      const options = {bubbles: true, clientX: rect.left + point.x, clientY: rect.top + point.y}
      target.dispatchEvent(new MouseEvent("mousedown", options))
      target.dispatchEvent(new MouseEvent("mouseup", options))
      target.dispatchEvent(new MouseEvent("click", options))
    JS

    expect(page).to have_css(".nm-graph-tooltip.is-pinned", text: notes.first.title, wait: 5)

    focus_state = page.evaluate_script(<<~JS)
      (() => {
        const controller = window.__graphDebug
        const camera = controller.state.renderer.getCamera().getState()
        return {
          focusedNodeId: controller.state.ui.focusedNodeId,
          ratio: camera.ratio
        }
      })()
    JS

    expect(focus_state["focusedNodeId"]).to eq(notes.first.id)
    expect(focus_state["ratio"]).to be < 1

    screenshot_path = Rails.root.join("tmp/graph-browser-spec.png")
    page.save_screenshot(screenshot_path, full: true)
    expect(File.exist?(screenshot_path)).to be(true)
  end
end
