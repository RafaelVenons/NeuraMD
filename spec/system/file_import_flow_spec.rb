# frozen_string_literal: true

require "rails_helper"

RSpec.describe "File import flow", type: :system do
  let(:user) { create(:user) }
  let(:fixture_path) { Rails.root.join("spec/fixtures/files/test_import.txt").to_s }

  before do
    login_as user, scope: :user
  end

  describe "uploading and processing a file" do
    before do
      allow(FileImports::ConvertService).to receive(:call) do |file_path:, **_opts|
        File.read(Rails.root.join("spec/fixtures/files/test_import.txt"))
      end
    end

    it "creates an import, shows preview, then confirms to create notes" do
      visit new_file_import_path

      # Hidden file input — use JS to make visible, then attach
      page.execute_script("document.querySelector('.fi-new__file-input').style.display = 'block'")
      find(".fi-new__file-input", visible: true).set(fixture_path)

      fill_in "file_import[base_tag]", with: "redes-neurais"

      click_button "Importar"

      # Wait for redirect to show page
      expect(page).to have_css(".fi-status", wait: 5)

      # Process the enqueued job (converts + generates preview)
      perform_enqueued_jobs

      # Reload to see preview state
      visit current_path

      expect(page).to have_css(".fi-status--preview", wait: 5)
      expect(page).to have_text("nota(s) sugerida(s)")
      expect(page).to have_css(".fi-preview__table")
      expect(page).to have_button("Confirmar e importar")

      # Confirm the import
      perform_enqueued_jobs do
        click_button "Confirmar e importar"
      end

      # After redirect + inline job, reload to see final state
      visit current_path

      expect(page).to have_css(".fi-status--completed", wait: 5)
      expect(page).to have_text("nota(s) criada(s)")
      expect(page).to have_text("Nota principal:")

      # Click on the status card — should navigate to the main note
      find("a.fi-status").click
      expect(page).to have_css(".cm-editor", wait: 10)
    end
  end

  describe "completed import actions" do
    let!(:note) do
      n = create(:note, title: "Imported Note")
      rev = n.note_revisions.create!(content_markdown: "Some content.", revision_kind: :checkpoint)
      n.update!(head_revision_id: rev.id)
      n
    end
    let!(:tag) { Tag.find_or_create_by!(name: "test-import-tag", tag_scope: "note") }
    let!(:import) do
      NoteTag.find_or_create_by!(note: note, tag: tag)
      create(:file_import, :completed, user: user,
             import_tag: tag.name,
             created_notes_data: [{ "slug" => note.slug, "title" => note.title }])
    end

    it "status card links to the main note" do
      visit file_import_path(import)

      expect(page).to have_text("Nota principal: #{note.title}")
      find("a.fi-status").click
      expect(page).to have_css(".cm-editor", wait: 10)
    end

    it "'Ver notas no grafo' navigates to the graph page" do
      visit file_import_path(import)

      click_link "Ver notas no grafo"

      expect(page).to have_css(".nm-graph-page", wait: 10)
    end
  end

  describe "completed import status" do
    let!(:import) do
      create(:file_import, :completed, user: user,
             converted_markdown: "# Test\n\nSome **markdown** content.")
    end

    it "shows main note title and links to it" do
      visit file_import_path(import)

      expect(page).to have_text("Nota principal:")
      expect(page).to have_css("a.fi-status")
    end
  end

  describe "preview state" do
    let!(:import) { create(:file_import, :preview, user: user) }

    it "shows split suggestion table and confirm button" do
      visit file_import_path(import)

      expect(page).to have_css(".fi-status--preview")
      expect(page).to have_text("nota(s) sugerida(s)")
      expect(page).to have_css(".fi-preview__table")
      expect(page).to have_button("Confirmar e importar")
    end
  end

  describe "retry failed import" do
    let!(:import) { create(:file_import, :failed, user: user) }

    before do
      allow(FileImports::ConvertService).to receive(:call) do |file_path:, **_opts|
        File.read(Rails.root.join("spec/fixtures/files/test_import.txt"))
      end
    end

    it "retries and reprocesses to preview" do
      visit file_import_path(import)

      expect(page).to have_text("Falhou")

      perform_enqueued_jobs do
        click_button "Tentar novamente"
      end

      # After redirect + inline job, reload to see final state
      visit current_path

      expect(page).to have_css(".fi-status--preview", wait: 5)
      expect(page).to have_text("nota(s) sugerida(s)")
    end
  end

  describe "delete import" do
    let!(:import) { create(:file_import, :completed, user: user) }

    it "removes import from history" do
      visit file_import_path(import)

      accept_confirm do
        click_button "Excluir"
      end

      expect(page).to have_current_path(file_imports_path, wait: 5)
      expect(page).not_to have_text(import.original_filename)
    end
  end
end
