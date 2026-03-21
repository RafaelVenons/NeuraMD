require "rails_helper"

RSpec.describe "Note shell navigation", type: :system do
  let(:user) { create(:user) }
  let!(:third_note) { create(:note, :with_head_revision, title: "Nota Terceira") }
  let!(:target_note) { create(:note, :with_head_revision, title: "Nota Destino") }
  let!(:source_note) { create(:note, :with_head_revision, title: "Nota Origem") }
  let!(:queued_request) do
    create(
      :ai_request,
      note_revision: source_note.head_revision,
      capability: "grammar_review",
      provider: "openai",
      requested_provider: "openai",
      model: "gpt-4o-mini",
      status: "queued",
      metadata: {"promise_note_title" => "Fila Persistente"}
    )
  end

  before do
    login_as user, scope: :user
    Notes::CheckpointService.call(
      note: source_note,
      content: "[[Nota Destino|#{target_note.id}]]",
      author: user
    )
    Notes::CheckpointService.call(
      note: target_note,
      content: "Conteudo destino shell",
      author: user
    )
    Notes::CheckpointService.call(
      note: third_note,
      content: "Conteudo terceira shell",
      author: user
    )
  end

  def editor_text
    page.evaluate_script(<<~JS)
      (() => {
        const host = document.querySelector("[data-controller~='codemirror']")
        const controller = window.Stimulus.controllers.find((item) => item.element === host && item.identifier === "codemirror")
        return controller.getValue()
      })()
    JS
  end

  def shell_navigate_to(path)
    expect(page).to have_css("#editor-root[data-note-shell-instance-id]", wait: 10)
    page.execute_script(<<~JS, path)
      const [targetPath] = arguments
      const root = document.getElementById("editor-root")
      const controller = window.Stimulus.controllers.find((item) => item.element === root && item.identifier === "note-shell")
      if (!controller) throw new Error("note-shell controller not found")
      controller.navigateTo(targetPath)
    JS
  end

  def shell_popstate_to(path)
    page.execute_script(<<~JS, path)
      const [targetPath] = arguments
      const root = document.getElementById("editor-root")
      const controller = window.Stimulus.controllers.find((item) => item.element === root && item.identifier === "note-shell")
      if (!controller) throw new Error("note-shell controller not found")
      window.history.replaceState({ noteShellPath: targetPath }, "", targetPath)
      controller._handlePopstate({ state: { noteShellPath: targetPath } })
    JS
  end

  def shell_instance_id
    find("#editor-root")["data-note-shell-instance-id"]
  end

  def embedded_graph_instance_id
    find(".note-graph-embed", visible: :all)["data-graph-instance-id"]
  end

  def embedded_graph_focused_note_id
    page.evaluate_script(<<~JS)
      (() => {
        const host = document.querySelector(".note-graph-embed")
        const controller = window.Stimulus.controllers.find((item) => item.element === host && item.identifier === "graph")
        return controller?.state?.ui?.focusedNodeId || null
      })()
    JS
  end

  def graph_navigate_to(path)
    page.execute_script(<<~JS, path)
      const [targetPath] = arguments
      const host = document.querySelector(".note-graph-embed")
      const controller = window.Stimulus.controllers.find((item) => item.element === host && item.identifier === "graph")
      if (!controller) throw new Error("embedded graph controller not found")
      controller.visit(targetPath)
    JS
  end

  def expect_shell_note(title:, path:)
    expect(page).to have_current_path(path, wait: 10)
    expect(page).to have_field(type: "text", with: title, wait: 10)
  end

  def travel_history(direction)
    direction.to_sym == :back ? page.go_back : page.go_forward
  end

  it "navigates between notes without remounting the editor shell" do
    visit note_path(source_note.slug)

    expect(page).to have_css(".cm-editor", wait: 10)
    expect(editor_text).to include("[[Nota Destino|#{target_note.id}]]")
    expect(page).to have_css("[data-ai-review-target='queueDock']:not(.hidden)", wait: 10)
    expect(page).to have_text("Fila Persistente")

    shell_instance = shell_instance_id
    shell_navigate_to(note_path(target_note.slug))

    expect_shell_note(title: "Nota Destino", path: note_path(target_note.slug))
    expect(page).to have_css("#editor-root", wait: 10)
    expect(shell_instance_id).to eq(shell_instance)
    expect(editor_text).to include("Conteudo destino shell")
    expect(page).to have_css("[data-ai-review-target='queueDock']:not(.hidden)", wait: 10)
    expect(page).to have_text("Fila Persistente")
  end

  it "supports browser back without remounting the editor shell" do
    visit note_path(source_note.slug)

    shell_navigate_to(note_path(target_note.slug))

    expect_shell_note(title: "Nota Destino", path: note_path(target_note.slug))

    travel_history(:back)

    expect_shell_note(title: "Nota Origem", path: note_path(source_note.slug))
    expect(page).to have_css("#editor-root", wait: 10)
    expect(editor_text).to include("[[Nota Destino|#{target_note.id}]]")
    expect(page).to have_text("Fila Persistente")
  end

  it "supports longer back and forward sequences without losing shell state" do
    visit note_path(source_note.slug)

    shell_instance = shell_instance_id
    graph_instance = embedded_graph_instance_id

    shell_navigate_to(note_path(target_note.slug))
    expect_shell_note(title: "Nota Destino", path: note_path(target_note.slug))

    shell_navigate_to(note_path(third_note.slug))
    expect_shell_note(title: "Nota Terceira", path: note_path(third_note.slug))

    shell_popstate_to(note_path(target_note.slug))
    expect_shell_note(title: "Nota Destino", path: note_path(target_note.slug))

    shell_popstate_to(note_path(source_note.slug))
    expect_shell_note(title: "Nota Origem", path: note_path(source_note.slug))

    shell_popstate_to(note_path(target_note.slug))
    expect_shell_note(title: "Nota Destino", path: note_path(target_note.slug))

    shell_popstate_to(note_path(third_note.slug))
    expect_shell_note(title: "Nota Terceira", path: note_path(third_note.slug))
    expect(shell_instance_id).to eq(shell_instance)
    expect(embedded_graph_instance_id).to eq(graph_instance)
    expect(embedded_graph_focused_note_id).to eq(third_note.id)
    expect(page).to have_text("Fila Persistente")
  end

  it "navigates via backlinks without remounting the shell or embedded graph" do
    visit note_path(target_note.slug)

    expect(page).to have_css(".note-graph-embed", wait: 10)
    shell_instance = shell_instance_id
    graph_instance = embedded_graph_instance_id

    find("[data-editor-target='contextMode']").find("option", text: "Backlinks").select_option
    expect(page).to have_css(".backlinks-panel a", text: source_note.title, wait: 10)

    find(".backlinks-panel a", text: source_note.title).click

    expect_shell_note(title: "Nota Origem", path: note_path(source_note.slug))
    expect(shell_instance_id).to eq(shell_instance)
    expect(embedded_graph_instance_id).to eq(graph_instance)
    expect(embedded_graph_focused_note_id).to eq(source_note.id)
    expect(page).to have_text("Fila Persistente")
  end

  it "navigates via note finder without remounting the shell or embedded graph" do
    visit note_path(source_note.slug)

    expect(page).to have_css(".note-graph-embed", wait: 10)
    shell_instance = shell_instance_id
    graph_instance = embedded_graph_instance_id

    find("button[title='Buscar notas (Ctrl+Shift+K)']").click
    expect(page).to have_css("[data-note-finder-target='dialog']:not(.hidden)", wait: 10)
    find("[data-note-finder-target='input']").set("Nota Destino")
    expect(page).to have_css(".note-finder-result", text: "Nota Destino", wait: 10)

    find(".note-finder-result", text: "Nota Destino", match: :first).click

    expect_shell_note(title: "Nota Destino", path: note_path(target_note.slug))
    expect(shell_instance_id).to eq(shell_instance)
    expect(embedded_graph_instance_id).to eq(graph_instance)
    expect(embedded_graph_focused_note_id).to eq(target_note.id)
    expect(page).to have_text("Fila Persistente")
  end

  it "navigates via the embedded graph without remounting the shell or graph" do
    visit note_path(source_note.slug)

    expect(page).to have_css(".note-graph-embed", wait: 10)
    shell_instance = shell_instance_id
    graph_instance = embedded_graph_instance_id

    graph_navigate_to(note_path(target_note.slug))

    expect_shell_note(title: "Nota Destino", path: note_path(target_note.slug))
    expect(shell_instance_id).to eq(shell_instance)
    expect(embedded_graph_instance_id).to eq(graph_instance)
    expect(embedded_graph_focused_note_id).to eq(target_note.id)
    expect(page).to have_text("Fila Persistente")
  end
end
