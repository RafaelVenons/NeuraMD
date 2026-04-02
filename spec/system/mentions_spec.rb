require "rails_helper"

RSpec.describe "Unlinked mentions panel", type: :system do
  let(:user) { create(:user) }
  let(:suffix) { SecureRandom.hex(4) }
  let!(:target) { create(:note, :with_head_revision, title: "Alvo #{suffix}") }

  before do
    login_as user, scope: :user
  end

  def create_note_with_content(title:, content:)
    note = create(:note, title: title)
    rev = create(:note_revision, note: note, content_markdown: content, revision_kind: :checkpoint)
    note.update_columns(head_revision_id: rev.id)
    note
  end

  it "shows unlinked mentions when switching to Menções panel" do
    create_note_with_content(title: "Fonte #{suffix}", content: "Este artigo discute Alvo #{suffix} em detalhes.")

    visit note_path(target.slug)
    expect(page).to have_css(".cm-editor", wait: 5)

    select "Menções", from: "Rodape"

    expect(page).to have_css(".mentions-panel:not(.hidden)", wait: 5)
    expect(page).to have_text("Fonte #{suffix}")
    expect(page).to have_css("mark", text: /Alvo #{suffix}/i)
    expect(page).to have_button("Linkar")
  end

  it "converts a mention to a wikilink when clicking Linkar" do
    source = create_note_with_content(title: "Fonte #{suffix}", content: "Discute Alvo #{suffix} aqui.")

    visit note_path(target.slug)
    expect(page).to have_css(".cm-editor", wait: 5)

    select "Menções", from: "Rodape"
    expect(page).to have_button("Linkar", wait: 5)

    click_button "Linkar"

    # After linking, the mention should disappear (or show empty message)
    expect(page).to have_text("Nenhuma menção não linkada", wait: 5)

    # Verify the source note now has a wikilink
    source.reload
    expect(source.head_revision.content_markdown).to include("[[Alvo #{suffix}|#{target.id}]]")
  end

  it "shows empty message when no mentions exist" do
    visit note_path(target.slug)
    expect(page).to have_css(".cm-editor", wait: 5)

    select "Menções", from: "Rodape"

    expect(page).to have_css(".mentions-panel:not(.hidden)", wait: 5)
    expect(page).to have_text("Nenhuma menção não linkada")
  end
end
