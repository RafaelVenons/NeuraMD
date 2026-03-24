require "rails_helper"

RSpec.describe "Graph browser", type: :system do
  let(:user) { create(:user) }

  before do
    login_as user, scope: :user
  end

  it "shows a controlled error when the graph endpoint returns HTML instead of JSON" do
    visit graph_path

    expect(page).to have_css("[data-controller='graph']", wait: 10)

    page.execute_script(<<~JS)
      (() => {
        const controller = window.__graphDebug
        controller.dataUrlValue = "/users/sign_in"
        controller.load()
      })()
    JS

    expect(page).to have_css("[data-graph-target='error']", text: "retornou HTML em vez de JSON", wait: 10)
    expect(page).not_to have_text("Unexpected token <")
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

    father_link = create(:note_link, src_note: notes.first, dst_note: notes.second, created_in_revision: notes.first.head_revision, hier_role: "target_is_parent")
    child_link = create(:note_link, src_note: notes.second, dst_note: notes.third, created_in_revision: notes.second.head_revision, hier_role: "target_is_child")
    create(:note_link, src_note: notes.third, dst_note: notes.fourth, created_in_revision: notes.third.head_revision, hier_role: "same_level")
    create(:note_link, src_note: notes.fourth, dst_note: notes.fifth, created_in_revision: notes.fourth.head_revision, hier_role: nil)
    create(:note_link, src_note: notes[4], dst_note: notes[5], created_in_revision: notes[4].head_revision, hier_role: "target_is_parent")

    visit graph_path

    expect(page).to have_css("[data-controller='graph']", wait: 10)
    expect(page).to have_css(".sigma-mouse", wait: 10)
    expect(page).to have_text("6 notas · 5 links", wait: 10)

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

    label_state = page.evaluate_script(<<~JS, notes.first.id)
      (() => {
        const nodeId = arguments[0]
        const controller = window.__graphDebug
        const renderer = controller.state.renderer
        renderer.refresh()

        return {
          labelRendererName: renderer.getSetting("defaultDrawNodeLabel")?.name || null,
          displayedLabels: Array.from(renderer.getNodeDisplayedLabels()),
          forceLabel: controller.state.display.nodes.get(nodeId)?.forceLabel || false
        }
      })()
    JS

    expect(label_state["labelRendererName"]).to eq("drawNodeLabelAbove")
    expect(label_state["displayedLabels"]).to include(notes.first.id)
    expect(label_state["forceLabel"]).to be(true)

    node_visual_state = page.evaluate_script(<<~JS, notes.first.id, notes.second.id)
      (() => {
        const [firstNodeId, secondNodeId] = arguments
        const controller = window.__graphDebug
        const firstNode = controller.state.graph.getNodeAttributes(firstNodeId)
        const secondNode = controller.state.graph.getNodeAttributes(secondNodeId)
        const edge = controller.state.graph.getEdgeAttributes(controller.state.graph.edges()[0])

        return {
          firstBaseSize: firstNode.baseSize,
          secondBaseSize: secondNode.baseSize,
          firstBorderColor: firstNode.borderColor,
          srcPadding: edge.srcPadding,
          dstPadding: edge.dstPadding,
          animationTick: controller._edgeAnimationTick
        }
      })()
    JS

    sleep 0.2

    later_animation_tick = page.evaluate_script("window.__graphDebug._edgeAnimationTick")

    expect(node_visual_state["firstBaseSize"]).to be < node_visual_state["secondBaseSize"]
    expect(node_visual_state["firstBorderColor"]).to be_present
    expect(node_visual_state["srcPadding"]).to eq(2)
    expect(node_visual_state["dstPadding"]).to eq(8)
    expect(later_animation_tick).to be > node_visual_state["animationTick"]

    arrow_geometry = page.evaluate_script(<<~JS, father_link.id, child_link.id)
      (() => {
        const [fatherEdgeId, childEdgeId] = arguments
        const controller = window.__graphDebug
        const father = controller.edgeArrowGeometry(fatherEdgeId)
        const child = controller.edgeArrowGeometry(childEdgeId)
        const fatherSource = controller.state.graph.getNodeAttributes(controller.state.graph.source(fatherEdgeId))
        const fatherTarget = controller.state.graph.getNodeAttributes(controller.state.graph.target(fatherEdgeId))
        const childTarget = controller.state.graph.getNodeAttributes(controller.state.graph.target(childEdgeId))
        const childSource = controller.state.graph.getNodeAttributes(controller.state.graph.source(childEdgeId))

        return {
          father,
          fatherSource,
          child,
          childTarget,
          fatherTarget,
          childSource
        }
      })()
    JS

    father_dx = arrow_geometry["fatherTarget"]["x"] - arrow_geometry["fatherSource"]["x"]
    father_dy = arrow_geometry["fatherTarget"]["y"] - arrow_geometry["fatherSource"]["y"]
    child_dx = arrow_geometry["childTarget"]["x"] - arrow_geometry["childSource"]["x"]
    child_dy = arrow_geometry["childTarget"]["y"] - arrow_geometry["childSource"]["y"]

    father_source_contact_progress = ((arrow_geometry["father"]["source"]["contact"]["x"] - arrow_geometry["fatherSource"]["x"]) * father_dx) + ((arrow_geometry["father"]["source"]["contact"]["y"] - arrow_geometry["fatherSource"]["y"]) * father_dy)
    father_target_contact_progress = ((arrow_geometry["father"]["target"]["contact"]["x"] - arrow_geometry["fatherSource"]["x"]) * father_dx) + ((arrow_geometry["father"]["target"]["contact"]["y"] - arrow_geometry["fatherSource"]["y"]) * father_dy)
    father_source_vertex_progresses = arrow_geometry["father"]["source"]["vertices"].map { |point| ((point["x"] - arrow_geometry["fatherSource"]["x"]) * father_dx) + ((point["y"] - arrow_geometry["fatherSource"]["y"]) * father_dy) }
    father_target_vertex_progresses = arrow_geometry["father"]["target"]["vertices"].map { |point| ((point["x"] - arrow_geometry["fatherSource"]["x"]) * father_dx) + ((point["y"] - arrow_geometry["fatherSource"]["y"]) * father_dy) }

    child_source_contact_progress = ((arrow_geometry["child"]["source"]["contact"]["x"] - arrow_geometry["childSource"]["x"]) * child_dx) + ((arrow_geometry["child"]["source"]["contact"]["y"] - arrow_geometry["childSource"]["y"]) * child_dy)
    child_target_contact_progress = ((arrow_geometry["child"]["target"]["contact"]["x"] - arrow_geometry["childSource"]["x"]) * child_dx) + ((arrow_geometry["child"]["target"]["contact"]["y"] - arrow_geometry["childSource"]["y"]) * child_dy)
    child_source_vertex_progresses = arrow_geometry["child"]["source"]["vertices"].map { |point| ((point["x"] - arrow_geometry["childSource"]["x"]) * child_dx) + ((point["y"] - arrow_geometry["childSource"]["y"]) * child_dy) }
    child_target_vertex_progresses = arrow_geometry["child"]["target"]["vertices"].map { |point| ((point["x"] - arrow_geometry["childSource"]["x"]) * child_dx) + ((point["y"] - arrow_geometry["childSource"]["y"]) * child_dy) }

    expect(arrow_geometry["father"]["source"]["vertices"].length).to be >= 6
    expect(arrow_geometry["father"]["target"]["vertices"].length).to be >= 6
    expect(arrow_geometry["child"]["source"]["vertices"].length).to be >= 6
    expect(arrow_geometry["child"]["target"]["vertices"].length).to be >= 6
    expect(father_source_vertex_progresses.max).to be > father_source_contact_progress
    expect(father_target_vertex_progresses.min).to be < father_target_contact_progress
    expect(child_source_vertex_progresses.max).to be > child_source_contact_progress
    expect(child_target_vertex_progresses.min).to be < child_target_contact_progress

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
    expect(focus_state["ratio"]).to be <= 1

    screenshot_path = Rails.root.join("tmp/graph-browser-spec.png")
    page.save_screenshot(screenshot_path, full: true)
    expect(File.exist?(screenshot_path)).to be(true)
  end

  it "creates a note from the floating header and focuses the title in the editor" do
    visit graph_path

    click_button "Nova nota"

    expect(page).to have_current_path(%r{/notes/[^/]+}, wait: 10)
    expect(page).to have_css("[data-editor-target='titleInput']", wait: 10)

    title_is_focused = page.evaluate_script(<<~JS)
      (() => {
        const input = document.querySelector("[data-editor-target='titleInput']")
        return document.activeElement === input
      })()
    JS

    expect(title_is_focused).to be(true)
    expect(page.find("[data-editor-target='titleInput']").value).to eq("Nova nota")
  end

  it "supports dragging nodes and arranges depth-1 neighbors by hierarchy" do
    root = create(:note, title: "Root")
    parent_note = create(:note, title: "Parent")
    child_note = create(:note, title: "Child")
    sibling_note = create(:note, title: "Sibling")
    neutral_note = create(:note, title: "Neutral")

    [root, parent_note, child_note, sibling_note, neutral_note].each do |note|
      revision = create(:note_revision, note:, content_markdown: "Resumo de #{note.title}")
      note.update_columns(head_revision_id: revision.id)
    end

    create(:note_link, src_note: root, dst_note: parent_note, created_in_revision: root.head_revision, hier_role: "target_is_parent")
    create(:note_link, src_note: root, dst_note: child_note, created_in_revision: root.head_revision, hier_role: "target_is_child")
    create(:note_link, src_note: root, dst_note: sibling_note, created_in_revision: root.head_revision, hier_role: "same_level")
    create(:note_link, src_note: neutral_note, dst_note: root, created_in_revision: neutral_note.head_revision, hier_role: nil)

    visit graph_path

    expect(page).to have_css(".sigma-mouse", wait: 10)

    page.execute_script(<<~JS, root.id)
      const rootId = arguments[0]
      const controller = window.__graphDebug
      controller.state.ui.focusedNodeId = rootId
      controller.state.ui.pinnedTooltipNodeId = rootId
      controller.state.ui.focusDepth = 1
      controller.applyDisplayState({ relayout: true, animateFocus: false })
    JS

    sleep 1.0

    hierarchy_positions = page.evaluate_script(<<~JS, root.id, parent_note.id, child_note.id, sibling_note.id, neutral_note.id)
      (() => {
        const [rootId, parentId, childId, siblingId, neutralId] = arguments
        const graph = window.__graphDebug.state.graph
        const pick = (id) => {
          const node = graph.getNodeAttributes(id)
          return { x: node.x, y: node.y }
        }

        return {
          root: pick(rootId),
          parent: pick(parentId),
          child: pick(childId),
          sibling: pick(siblingId),
          neutral: pick(neutralId)
        }
      })()
    JS

    expect(hierarchy_positions["parent"]["y"]).to be < hierarchy_positions["root"]["y"]
    expect(hierarchy_positions["child"]["y"]).to be > hierarchy_positions["root"]["y"]
    expect((hierarchy_positions["sibling"]["x"] - hierarchy_positions["root"]["x"]).abs).to be > 0.01
    expect((hierarchy_positions["neutral"]["x"] - hierarchy_positions["root"]["x"]).abs).to be > 0.01
    expect((hierarchy_positions["neutral"]["y"] - hierarchy_positions["root"]["y"]).abs).to be > 0.01

    drag_result = page.evaluate_script(<<~JS, child_note.id)
      (() => {
        const nodeId = arguments[0]
        const controller = window.__graphDebug
        const renderer = controller.state.renderer
        const target = document.querySelector(".sigma-mouse")
        const node = renderer.getNodeDisplayData(nodeId)
        const start = renderer.graphToViewport({ x: node.x, y: node.y })
        const finish = { x: start.x + 90, y: start.y + 50 }
        const rect = target.getBoundingClientRect()
        const eventAt = (type, point) => new MouseEvent(type, {
          bubbles: true,
          clientX: rect.left + point.x,
          clientY: rect.top + point.y
        })

        target.dispatchEvent(eventAt("mousedown", start))
        window.dispatchEvent(eventAt("mousemove", finish))
        window.dispatchEvent(eventAt("mouseup", finish))

        const moved = controller.state.graph.getNodeAttributes(nodeId)
        const manual = controller.state.layout.manualPositions.get(nodeId)

        return {
          before: { x: node.x, y: node.y },
          after: { x: moved.x, y: moved.y },
          manual
        }
      })()
    JS

    expect((drag_result["after"]["x"] - drag_result["before"]["x"]).abs).to be > 0.005
    expect((drag_result["after"]["y"] - drag_result["before"]["y"]).abs).to be > 0.005
    expect(drag_result["manual"]).not_to be_nil
  end

  it "toggles note-tag associations from the graph sidebar when a node is focused" do
    focused_note = create(:note, title: "Foco")
    neighbor_note = create(:note, title: "Vizinha")
    tag = create(:tag, name: "clinica", color_hex: "#3ba99c", tag_scope: "both")

    [focused_note, neighbor_note].each do |note|
      revision = create(:note_revision, note:, content_markdown: "Resumo de #{note.title}")
      note.update_columns(head_revision_id: revision.id)
    end

    create(:note_link, src_note: focused_note, dst_note: neighbor_note, created_in_revision: focused_note.head_revision, hier_role: "same_level")
    NoteTag.create!(note: neighbor_note, tag: tag)

    visit graph_path

    expect(page).to have_css(".sigma-mouse", wait: 10)
    expect(page).to have_css("[data-tag-id='#{tag.id}']", wait: 10)

    page.execute_script(<<~JS, focused_note.id)
      const nodeId = arguments[0]
      const controller = window.__graphDebug
      controller.enterFocusMode(nodeId)
    JS

    expect(page).to have_css("[data-tag-id='#{tag.id}'][aria-pressed='false']", wait: 5)

    find("[data-tag-id='#{tag.id}']").click

    expect(page).to have_css("[data-tag-id='#{tag.id}'].is-attached[aria-pressed='true']", wait: 5)
    expect(NoteTag.where(note: focused_note, tag: tag).count).to eq(1)

    find("[data-tag-id='#{tag.id}']").click

    expect(page).to have_css("[data-tag-id='#{tag.id}'][aria-pressed='false']", wait: 5)
    expect(page).not_to have_css("[data-tag-id='#{tag.id}'].is-attached", wait: 5)
    expect(NoteTag.where(note: focused_note, tag: tag).count).to eq(0)
  end

  it "moves a newly attached tag to the top of the graph sidebar" do
    focused_note = create(:note, title: "Foco")
    helper_note = create(:note, title: "Helper")
    alpha_tag = create(:tag, name: "alpha", color_hex: "#3ba99c", tag_scope: "both")
    zeta_tag = create(:tag, name: "zeta", color_hex: "#f97316", tag_scope: "both")

    [focused_note, helper_note].each do |note|
      revision = create(:note_revision, note:, content_markdown: "Resumo")
      note.update_columns(head_revision_id: revision.id)
    end
    NoteTag.create!(note: helper_note, tag: alpha_tag)
    NoteTag.create!(note: helper_note, tag: zeta_tag)

    visit graph_path

    expect(page).to have_css(".sigma-mouse", wait: 10)

    page.execute_script(<<~JS, focused_note.id)
      const controller = window.__graphDebug
      controller.enterFocusMode(arguments[0])
    JS

    expect(page).to have_css(".nm-graph__tag-row", minimum: 2, wait: 5)

    before_names = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll(".nm-graph__tag-row")).map((row) => row.textContent.trim())
    JS

    expect(before_names.first(2)).to eq(%w[alpha zeta])

    find("[data-tag-id='#{zeta_tag.id}']").click

    after_names = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll(".nm-graph__tag-row")).map((row) => row.textContent.trim())
    JS

    expect(after_names.first).to eq("zeta")
    expect(page).to have_css("[data-tag-id='#{zeta_tag.id}'].is-attached[aria-pressed='true']", wait: 5)
  end

  it "replaces the tags title with a cosine-ranked search field" do
    focused_note = create(:note, title: "Foco")
    helper_note = create(:note, title: "Helper")
    cardio_long = create(:tag, name: "cardiologia", color_hex: "#3ba99c", tag_scope: "both")
    cardio_short = create(:tag, name: "cardio geral", color_hex: "#38bdf8", tag_scope: "both")
    neuro_tag = create(:tag, name: "neurologia", color_hex: "#f97316", tag_scope: "both")

    [focused_note, helper_note].each do |note|
      revision = create(:note_revision, note:, content_markdown: "Resumo")
      note.update_columns(head_revision_id: revision.id)
    end
    NoteTag.create!(note: focused_note, tag: cardio_long)
    NoteTag.create!(note: focused_note, tag: cardio_short)
    NoteTag.create!(note: helper_note, tag: neuro_tag)

    visit graph_path

    expect(page).to have_css(".sigma-mouse", wait: 10)
    click_button "Tags"

    expect(page).to have_css("[data-graph-target='tagSearch']:not([hidden])", wait: 5)

    find("[data-graph-target='tagSearch']").fill_in with: "cardio"

    names = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll(".nm-graph__tag-row")).map((row) => row.textContent.trim())
    JS

    expect(names).to eq(["cardio geral", "cardiologia"])
    expect(page).not_to have_css(".nm-graph__tag-row", text: "neurologia")
  end

  it "moves the focused node tags to the top of the graph sidebar" do
    focused_note = create(:note, title: "Foco")
    helper_note = create(:note, title: "Helper")
    alpha_tag = create(:tag, name: "alpha", color_hex: "#3ba99c", tag_scope: "both")
    beta_tag = create(:tag, name: "beta", color_hex: "#38bdf8", tag_scope: "both")
    zeta_tag = create(:tag, name: "zeta", color_hex: "#f97316", tag_scope: "both")

    [focused_note, helper_note].each do |note|
      revision = create(:note_revision, note:, content_markdown: "Resumo")
      note.update_columns(head_revision_id: revision.id)
    end
    NoteTag.create!(note: focused_note, tag: zeta_tag)
    NoteTag.create!(note: focused_note, tag: beta_tag)
    NoteTag.create!(note: helper_note, tag: alpha_tag)

    visit graph_path

    expect(page).to have_css(".sigma-mouse", wait: 10)

    before_names = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll(".nm-graph__tag-row")).map((row) => row.textContent.trim())
    JS

    expect(before_names.first(3)).to eq(%w[alpha beta zeta])

    page.execute_script(<<~JS, focused_note.id)
      const controller = window.__graphDebug
      controller.enterFocusMode(arguments[0])
    JS

    after_names = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll(".nm-graph__tag-row")).map((row) => row.textContent.trim())
    JS

    expect(after_names.first(2)).to eq(%w[beta zeta])
  end

  it "leaves tag attachment mode on background click and applies tag filters to nodes and edges" do
    focused_note = create(:note, title: "Foco")
    neighbor_note = create(:note, title: "Vizinha")
    edge_src = create(:note, title: "Origem da aresta")
    edge_dst = create(:note, title: "Destino da aresta")
    hidden_note = create(:note, title: "Oculta")
    filter_tag = create(:tag, name: "clinica", color_hex: "#3ba99c", tag_scope: "both")

    [focused_note, neighbor_note, edge_src, edge_dst, hidden_note].each do |note|
      revision = create(:note_revision, note:, content_markdown: "Resumo de #{note.title}")
      note.update_columns(head_revision_id: revision.id)
    end

    ghost_edge = create(:note_link, src_note: focused_note, dst_note: neighbor_note, created_in_revision: focused_note.head_revision, hier_role: "same_level")
    tagged_edge = create(:note_link, src_note: edge_src, dst_note: edge_dst, created_in_revision: edge_src.head_revision, hier_role: "target_is_parent")
    create(:note_link, src_note: hidden_note, dst_note: neighbor_note, created_in_revision: hidden_note.head_revision, hier_role: "target_is_child")

    NoteTag.create!(note: focused_note, tag: filter_tag)
    LinkTag.create!(note_link: tagged_edge, tag: filter_tag)

    visit graph_path

    expect(page).to have_css(".sigma-mouse", wait: 10)

    page.execute_script(<<~JS, focused_note.id)
      const controller = window.__graphDebug
      controller.enterFocusMode(arguments[0])
    JS

    expect(page).to have_css("[data-tag-id='#{filter_tag.id}'].is-attached[aria-pressed='true']", wait: 5)

    page.execute_script(<<~JS)
      const controller = window.__graphDebug
      const target = document.querySelector(".sigma-mouse")
      const rect = target.getBoundingClientRect()
      const candidates = [
        { x: rect.width * 0.04, y: rect.height * 0.08 },
        { x: rect.width * 0.96, y: rect.height * 0.08 },
        { x: rect.width * 0.04, y: rect.height * 0.92 },
        { x: rect.width * 0.96, y: rect.height * 0.92 }
      ]
      const point = candidates.find((candidate) => {
        return !controller.nodeAtPointer({
          clientX: rect.left + candidate.x,
          clientY: rect.top + candidate.y
        })
      }) || candidates[0]

      target.dispatchEvent(new MouseEvent("click", {
        bubbles: true,
        clientX: rect.left + point.x,
        clientY: rect.top + point.y
      }))
    JS

    expect(page).to have_css("[data-tag-id='#{filter_tag.id}'][aria-pressed='false']", wait: 5)
    expect(page).not_to have_css("[data-tag-id='#{filter_tag.id}'].is-attached", wait: 5)

    find("[data-tag-id='#{filter_tag.id}']").click

    expect(page).to have_css("[data-tag-id='#{filter_tag.id}'].is-selected[aria-pressed='true']", wait: 5)

    filter_state = page.evaluate_script(<<~JS, focused_note.id, neighbor_note.id, edge_src.id, edge_dst.id, hidden_note.id, ghost_edge.id, tagged_edge.id)
      (() => {
        const [focusedNodeId, neighborNodeId, edgeSrcId, edgeDstId, hiddenNodeId, ghostEdgeId, taggedEdgeId] = arguments
        const controller = window.__graphDebug
        const nodes = controller.state.display.nodes
        const edges = controller.state.display.edges

        const ghostEdgeDisplay = edges.get(ghostEdgeId)
        const taggedEdgeDisplay = edges.get(taggedEdgeId)

        return {
          focusedNode: nodes.get(focusedNodeId),
          neighborNode: nodes.get(neighborNodeId),
          edgeSrcNode: nodes.get(edgeSrcId),
          edgeDstNode: nodes.get(edgeDstId),
          hiddenNode: nodes.get(hiddenNodeId),
          ghostEdge: ghostEdgeDisplay,
          taggedEdge: taggedEdgeDisplay
        }
      })()
    JS

    expect(filter_state["focusedNode"]["hidden"]).to be(false)
    expect(filter_state["focusedNode"]["filterState"]).to eq("normal")
    expect(filter_state["neighborNode"]["hidden"]).to be(false)
    expect(filter_state["neighborNode"]["filterState"]).to eq("ghost")
    expect(filter_state["edgeSrcNode"]["hidden"]).to be(false)
    expect(filter_state["edgeDstNode"]["hidden"]).to be(false)
    expect(filter_state["hiddenNode"]["hidden"]).to be(true)
    expect(filter_state["ghostEdge"]["hidden"]).to be(false)
    expect(filter_state["ghostEdge"]["ghostedByTagFilter"]).to be(true)
    expect(filter_state["ghostEdge"]["color"]).to include("rgba(")
    expect(filter_state["taggedEdge"]["hidden"]).to be(false)
    expect(filter_state["taggedEdge"]["ghostedByTagFilter"]).to be(false)
  end

  it "focuses the current note in the embedded graph and navigates on simple click to another note" do
    current_note = create(:note, title: "Atual")
    neighbor_note = create(:note, title: "Vizinha")
    distant_note = create(:note, title: "Distante")

    [current_note, neighbor_note, distant_note].each do |note|
      revision = create(:note_revision, note:, content_markdown: "Resumo de #{note.title}")
      note.update_columns(head_revision_id: revision.id)
    end

    create(:note_link, src_note: current_note, dst_note: neighbor_note, created_in_revision: current_note.head_revision, hier_role: "target_is_child")
    create(:note_link, src_note: neighbor_note, dst_note: distant_note, created_in_revision: neighbor_note.head_revision, hier_role: "same_level")

    visit note_path(current_note.slug)

    expect(page).to have_css(".note-graph-embed[data-controller='graph']", wait: 10)
    expect(page).to have_css(".note-graph-embed .sigma-mouse", wait: 10)

    embedded_state = page.evaluate_script(<<~JS)
      (() => {
        const controller = window.__graphDebug
        const focusedNode = controller.state.graph.getNodeAttributes(controller.state.ui.focusedNodeId)
        const focusedNodeState = controller.state.display.nodes.get(controller.state.ui.focusedNodeId)
        const focusedNodeDisplay = controller.state.renderer.getNodeDisplayData(controller.state.ui.focusedNodeId)
        const firstEdgeId = controller.state.graph.edges()[0]
        const focusedEdge = controller.state.graph.getEdgeAttributes(firstEdgeId)
        const focusedEdgeState = controller.state.display.edges.get(firstEdgeId)
        const focusedEdgeDisplay = controller.state.renderer.getEdgeDisplayData(firstEdgeId)
        const camera = controller.state.renderer.getCamera().getState()
        return {
          focusedNodeId: controller.state.ui.focusedNodeId,
          pinnedTooltipNodeId: controller.state.ui.pinnedTooltipNodeId,
          focusDepth: controller.state.ui.focusDepth,
          focusedNodeBaseSize: focusedNode.size,
          focusedNodeStateSize: focusedNodeState.size,
          focusedNodeDisplaySize: focusedNodeDisplay.size,
          focusedEdgeSize: focusedEdge.size,
          focusedEdgeStateSize: focusedEdgeState.size,
          focusedEdgeDisplaySize: focusedEdgeDisplay.size,
          focusedEdgeSrcPadding: focusedEdge.srcPadding,
          focusedEdgeDisplaySrcPadding: focusedEdgeDisplay.srcPadding,
          focusedEdgeDstPadding: focusedEdge.dstPadding,
          focusedEdgeDisplayDstPadding: focusedEdgeDisplay.dstPadding,
          cameraRatio: camera.ratio
        }
      })()
    JS

    expect(embedded_state).to include(
      "focusedNodeId" => current_note.id,
      "pinnedTooltipNodeId" => nil,
      "focusDepth" => 2
    )
    expect(embedded_state["focusedNodeDisplaySize"]).to be_within(0.01).of(embedded_state["focusedNodeStateSize"] * 0.5)
    expect(embedded_state["focusedEdgeDisplaySize"]).to be_within(0.01).of(embedded_state["focusedEdgeStateSize"] * 0.5)
    expect(embedded_state["focusedEdgeDisplaySrcPadding"]).to be_within(0.01).of(embedded_state["focusedEdgeSrcPadding"] * 0.5)
    expect(embedded_state["focusedEdgeDisplayDstPadding"]).to be_within(0.01).of(embedded_state["focusedEdgeDstPadding"] * 0.5)
    expect(embedded_state["cameraRatio"]).to be < 0.48
    expect(page).not_to have_css(".nm-graph-tooltip")

    page.execute_script(<<~JS, neighbor_note.id)
      const nodeId = arguments[0]
      const controller = window.__graphDebug
      const renderer = controller.state.renderer
      const node = renderer.getNodeDisplayData(nodeId)
      const point = renderer.graphToViewport({ x: node.x, y: node.y })
      const target = document.querySelector(".note-graph-embed .sigma-mouse")
      const rect = target.getBoundingClientRect()
      const options = {
        bubbles: true,
        clientX: rect.left + point.x,
        clientY: rect.top + point.y
      }

      target.dispatchEvent(new MouseEvent("mousedown", options))
      window.dispatchEvent(new MouseEvent("mouseup", options))
    JS

    expect(page).to have_current_path(note_path(neighbor_note.slug), wait: 10)
    expect(page).to have_css(".note-graph-embed[data-controller='graph']", wait: 10)

    next_embedded_state = page.evaluate_script(<<~JS)
      (() => {
        const controller = window.__graphDebug
        return {
          focusedNodeId: controller.state.ui.focusedNodeId,
          pinnedTooltipNodeId: controller.state.ui.pinnedTooltipNodeId,
          focusDepth: controller.state.ui.focusDepth
        }
      })()
    JS

    expect(next_embedded_state).to include(
      "focusedNodeId" => neighbor_note.id,
      "pinnedTooltipNodeId" => nil,
      "focusDepth" => 2
    )
    expect(page).not_to have_css(".nm-graph-tooltip")
  end

  it "keeps a newly created linked note within the focus ring range in the embedded graph" do
    suffix = SecureRandom.hex(4)
    current_note = create(:note, title: "Atual #{suffix}")
    existing_neighbor = create(:note, title: "Vizinha #{suffix}")

    [current_note, existing_neighbor].each do |note|
      revision = create(:note_revision, note:, content_markdown: "Resumo de #{note.title}")
      note.update_columns(head_revision_id: revision.id)
    end

    create(:note_link, src_note: current_note, dst_note: existing_neighbor, created_in_revision: current_note.head_revision, hier_role: "target_is_child")

    visit note_path(current_note.slug)

    expect(page).to have_css(".note-graph-embed .sigma-mouse", wait: 10)

    new_note = create(:note, title: "Nova ligada #{suffix}")
    new_revision = create(:note_revision, note: new_note, content_markdown: "Resumo de Nova ligada #{suffix}")
    new_note.update_columns(head_revision_id: new_revision.id)
    create(:note_link, src_note: current_note, dst_note: new_note, created_in_revision: current_note.head_revision, hier_role: "same_level")

    page.execute_script(<<~JS)
      (() => {
        const controller = window.__graphDebug
        controller._pendingGraphSnapshot = controller.captureGraphSnapshot()
        controller.load()
      })()
    JS

    expect(page).to have_css(".note-graph-embed .sigma-mouse", wait: 10)
    Timeout.timeout(10) do
      loop do
        present = page.evaluate_script(<<~JS, new_note.id)
          (() => {
            const nodeId = arguments[0]
            return window.__graphDebug.state.graph.hasNode(nodeId)
          })()
        JS
        break if present

        sleep 0.1
      end
    end

    ring_state = page.evaluate_script(<<~JS, current_note.id, existing_neighbor.id, new_note.id)
      (() => {
        const [focusId, existingId, newId] = arguments
        const graph = window.__graphDebug.state.graph
        const focus = graph.getNodeAttributes(focusId)
        const existing = graph.getNodeAttributes(existingId)
        const created = graph.getNodeAttributes(newId)
        const distance = (from, to) => Math.hypot(to.x - from.x, to.y - from.y)

        return {
          existingDistance: distance(focus, existing),
          createdDistance: distance(focus, created)
        }
      })()
    JS

    expect(ring_state["createdDistance"]).to be > 0.02
    expect(ring_state["createdDistance"]).to be < 0.1
  end

  it "navigates to /graph on double click over the embedded graph background" do
    current_note = create(:note, title: "Atual")
    neighbor_note = create(:note, title: "Vizinha")

    [current_note, neighbor_note].each do |note|
      revision = create(:note_revision, note:, content_markdown: "Resumo de #{note.title}")
      note.update_columns(head_revision_id: revision.id)
    end

    create(:note_link, src_note: current_note, dst_note: neighbor_note, created_in_revision: current_note.head_revision, hier_role: "target_is_child")

    visit note_path(current_note.slug)

    expect(page).to have_css(".note-graph-embed .sigma-mouse", wait: 10)

    page.execute_script(<<~JS)
      const target = document.querySelector(".note-graph-embed .sigma-mouse")
      const rect = target.getBoundingClientRect()
      const options = {
        bubbles: true,
        clientX: rect.left + (rect.width * 0.08),
        clientY: rect.top + (rect.height * 0.12)
      }

      target.dispatchEvent(new MouseEvent("dblclick", options))
    JS

    expect(page).to have_current_path(graph_path, wait: 10)
    expect(page).to have_css("[data-controller='graph']", wait: 10)
  end

  it "recovers from a node dragged extremely far away via force relaxation on focus" do
    notes = Array.new(5) do |index|
      note = create(:note, title: "Force #{index + 1}")
      revision = create(:note_revision, note:, content_markdown: "Content #{index + 1}")
      note.update_columns(head_revision_id: revision.id)
      note
    end

    create(:note_link, src_note: notes[0], dst_note: notes[1], created_in_revision: notes[0].head_revision, hier_role: "target_is_parent")
    create(:note_link, src_note: notes[0], dst_note: notes[2], created_in_revision: notes[0].head_revision, hier_role: "target_is_child")
    create(:note_link, src_note: notes[1], dst_note: notes[3], created_in_revision: notes[1].head_revision, hier_role: "same_level")
    create(:note_link, src_note: notes[2], dst_note: notes[4], created_in_revision: notes[2].head_revision, hier_role: nil)

    visit graph_path
    expect(page).to have_css(".sigma-mouse", wait: 10)
    expect(page).to have_text("5 notas · 4 links", wait: 10)

    # Capture initial positions and verify nodes are spread out
    initial_state = page.evaluate_script(<<~JS, notes.map(&:id))
      (() => {
        const ids = arguments[0]
        const graph = window.__graphDebug.state.graph
        const positions = ids.map((id) => {
          const n = graph.getNodeAttributes(id)
          return { id, x: n.x, y: n.y }
        })
        return positions
      })()
    JS

    # Verify initial layout has reasonable spread (no overlaps)
    initial_min_dist = compute_min_pairwise_distance(initial_state)
    expect(initial_min_dist).to be > 0.001, "Initial layout should have spread-out nodes"

    # Drag a node extremely far (1000x the graph extent)
    page.execute_script(<<~JS, notes[1].id)
      (() => {
        const nodeId = arguments[0]
        const controller = window.__graphDebug
        const graph = controller.state.graph
        const attrs = graph.getNodeAttributes(nodeId)

        const extremeX = attrs.x + 100
        const extremeY = attrs.y + 100
        graph.mergeNodeAttributes(nodeId, { x: extremeX, y: extremeY })
        controller.state.layout.manualPositions.set(nodeId, { x: extremeX, y: extremeY })
        if (controller.state.layout.basePositions?.has(nodeId)) {
          controller.state.layout.basePositions.set(nodeId, { x: extremeX, y: extremeY })
        }
        controller.state.renderer.refresh()
      })()
    JS

    sleep 0.3

    # Trigger relayout so constrainViewportExtent collapses the non-extreme nodes
    page.execute_script(<<~JS)
      window.__graphDebug.applyDisplayState({ relayout: true, animateFocus: false })
    JS

    sleep 1.0

    # Verify the graph is now degenerate — non-extreme nodes overlap after scaling
    degenerate_state = page.evaluate_script(<<~JS, notes.map(&:id))
      (() => {
        const ids = arguments[0]
        const graph = window.__graphDebug.state.graph
        return ids.map((id) => {
          const n = graph.getNodeAttributes(id)
          return { id, x: n.x, y: n.y }
        })
      })()
    JS

    degenerate_min_dist = compute_min_pairwise_distance(degenerate_state)
    expect(degenerate_min_dist).to be < initial_min_dist,
      "After extreme drag + relayout, nodes should collapse (min: #{degenerate_min_dist} vs initial: #{initial_min_dist})"

    # Enter focus mode — should trigger force relaxation and clear manual positions
    page.execute_script(<<~JS, notes[0].id)
      window.__graphDebug.enterFocusMode(arguments[0])
    JS

    sleep 1.5

    # Verify recovery: nodes should be spread out, no overlaps
    recovered_state = page.evaluate_script(<<~JS, notes.map(&:id))
      (() => {
        const ids = arguments[0]
        const graph = window.__graphDebug.state.graph
        const positions = ids.map((id) => {
          const n = graph.getNodeAttributes(id)
          return { id, x: n.x, y: n.y }
        })
        return positions
      })()
    JS

    recovered_min_dist = compute_min_pairwise_distance(recovered_state)
    expect(recovered_min_dist).to be > 0.001,
      "After focus mode, force relaxation should spread nodes apart (min dist: #{recovered_min_dist})"

    # Verify edge lengths are reasonable (not extremely long or short)
    edge_stats = page.evaluate_script(<<~JS, notes.map(&:id))
      (() => {
        const graph = window.__graphDebug.state.graph
        const lengths = []
        graph.forEachEdge((_, _attrs, src, dst) => {
          const s = graph.getNodeAttributes(src)
          const d = graph.getNodeAttributes(dst)
          lengths.push(Math.hypot(d.x - s.x, d.y - s.y))
        })
        lengths.sort((a, b) => a - b)
        return {
          min: lengths[0],
          max: lengths[lengths.length - 1],
          ratio: lengths.length > 1 ? lengths[lengths.length - 1] / Math.max(lengths[0], 0.0001) : 1
        }
      })()
    JS

    expect(edge_stats["min"]).to be > 0.0005,
      "Shortest edge should have meaningful length"
    expect(edge_stats["ratio"]).to be < 50,
      "Edge length ratio (max/min) should be bounded, got #{edge_stats['ratio']}"
  end

  private

  def compute_min_pairwise_distance(positions)
    min_dist = Float::INFINITY
    positions.each_with_index do |a, i|
      positions[(i + 1)..].each do |b|
        dist = Math.sqrt((a["x"] - b["x"])**2 + (a["y"] - b["y"])**2)
        min_dist = dist if dist < min_dist
      end
    end
    min_dist
  end
end
