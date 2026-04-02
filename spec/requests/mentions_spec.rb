require "rails_helper"

RSpec.describe "Mentions", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "POST /notes/:slug/convert_mention" do
    let(:target) { create(:note, :with_head_revision, title: "Neurociência") }
    let(:source) do
      note = create(:note, title: "Artigo")
      rev = create(:note_revision, note: note, content_markdown: "Sobre Neurociência aqui.", revision_kind: :checkpoint)
      note.update_columns(head_revision_id: rev.id)
      note
    end

    it "converts a mention to a wikilink and returns updated mentions HTML" do
      post convert_mention_note_path(target.slug), params: {
        source_slug: source.slug,
        matched_term: "Neurociência"
      }, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["linked"]).to be true
      expect(body["graph_changed"]).to be true
      expect(body["mentions_html"]).to be_a(String)

      source.reload
      expect(source.head_revision.content_markdown).to include("[[Neurociência|#{target.id}]]")
    end

    it "requires authentication" do
      sign_out user
      post convert_mention_note_path(target.slug), params: {
        source_slug: source.slug,
        matched_term: "Neurociência"
      }, as: :json

      expect(response.status).to be_in([302, 401])
    end

    it "returns 404 for invalid source_slug" do
      post convert_mention_note_path(target.slug), params: {
        source_slug: "nonexistent",
        matched_term: "Neurociência"
      }, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /notes/:slug (shell payload)" do
    it "includes mentions HTML in the shell payload" do
      target = create(:note, :with_head_revision, title: "Café")
      source = create(:note, title: "Receita")
      rev = create(:note_revision, note: source, content_markdown: "Receita de Café especial.")
      source.update_columns(head_revision_id: rev.id)

      get note_path(target.slug), headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["html"]["mentions"]).to include("Receita")
      expect(body["urls"]["convert_mention"]).to be_present
    end
  end
end
