require "rails_helper"

RSpec.describe "AI review", type: :system do
  let(:user) { create(:user) }
  let(:note) { create(:note, :with_head_revision) }

  before do
    allow(Ai::ReviewService).to receive(:status).and_return(
      {
        enabled: true,
        provider: "openai",
        model: "gpt-4o-mini",
        available_providers: ["openai"]
      }
    )

    allow(Ai::ReviewService).to receive(:call).and_return(
      Ai::Result.new(
        content: "Texto corrigido pela IA.",
        provider: "openai",
        model: "gpt-4o-mini"
      )
    )

    login_as user, scope: :user
    visit note_path(note.slug)
    expect(page).to have_css(".cm-editor", wait: 5)
  end

  it "applies the AI grammar review to the editor content" do
    find("button[title='Revisar gramática com IA']").click

    expect(page).to have_css("dialog[open]", text: "Revisão com IA", wait: 5)
    expect(page).to have_text("Texto corrigido pela IA.")

    click_button "Aplicar"

    expect(page).to have_css(".cm-content", text: "Texto corrigido pela IA.", wait: 5)
  end

  it "opens the rewrite action from the toolbar" do
    find("button[title='Reescrever com IA']").click

    expect(page).to have_css("dialog[open]", text: "Revisão com IA", wait: 5)
    expect(page).to have_text("Texto corrigido pela IA.")
  end
end
