require "rails_helper"

RSpec.describe "NoteViews", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "POST /views" do
    it "creates a view and returns JSON" do
      post note_views_path, params: {
        note_view: {name: "Neuro Notes", filter_query: "tag:neuro", display_type: "table", columns: ["title", "status"]}
      }, as: :json

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["name"]).to eq("Neuro Notes")
      expect(body["filter_query"]).to eq("tag:neuro")
      expect(body["columns"]).to eq(["title", "status"])
    end

    it "returns errors for invalid params" do
      post note_views_path, params: {
        note_view: {name: "", display_type: "table"}
      }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"]).to be_present
    end
  end

  describe "PATCH /views/:id" do
    it "updates view config" do
      view = create(:note_view, name: "Old Name")

      patch note_view_path(view), params: {
        note_view: {name: "New Name", display_type: "card"}
      }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["name"]).to eq("New Name")
      expect(response.parsed_body["display_type"]).to eq("card")
    end
  end

  describe "DELETE /views/:id" do
    it "destroys the view" do
      view = create(:note_view)

      expect { delete note_view_path(view), as: :json }
        .to change(NoteView, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end

  describe "GET /views/:id/results" do
    let!(:user_for_notes) { user }

    def create_noted(title, content: "Conteudo de #{title}")
      note = create(:note, title: title)
      Notes::CheckpointService.call(note: note, content: content, author: user_for_notes)
      note.reload
    end

    it "returns all notes when filter is empty" do
      create_noted("Note A")
      create_noted("Note B")
      view = create(:note_view, filter_query: "")

      get results_note_view_path(view), as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["notes"].size).to eq(2)
    end

    it "filters notes by DSL query" do
      tagged = create_noted("Tagged Note")
      tag = create(:tag, name: "neuro")
      NoteTag.create!(note: tagged, tag: tag)
      _other = create_noted("Other Note")

      view = create(:note_view, filter_query: "tag:neuro")

      get results_note_view_path(view), as: :json

      body = response.parsed_body
      titles = body["notes"].map { |n| n["title"] }
      expect(titles).to include("Tagged Note")
      expect(titles).not_to include("Other Note")
    end

    it "sorts by property value" do
      a = create_noted("Alpha")
      a.head_revision.update!(properties_data: {"priority" => "1"})
      b = create_noted("Beta")
      b.head_revision.update!(properties_data: {"priority" => "2"})

      view = create(:note_view,
        filter_query: "",
        sort_config: {"field" => "priority", "direction" => "asc"})

      get results_note_view_path(view), as: :json

      titles = response.parsed_body["notes"].map { |n| n["title"] }
      expect(titles).to eq(["Alpha", "Beta"])
    end

    it "sorts by title" do
      create_noted("Zebra")
      create_noted("Alpha")

      view = create(:note_view, sort_config: {"field" => "title", "direction" => "asc"})

      get results_note_view_path(view), as: :json

      titles = response.parsed_body["notes"].map { |n| n["title"] }
      expect(titles).to eq(["Alpha", "Zebra"])
    end

    it "paginates results" do
      55.times { |i| create_noted("Note #{i.to_s.rjust(3, "0")}") }
      view = create(:note_view, sort_config: {"field" => "title", "direction" => "asc"})

      get results_note_view_path(view), as: :json
      body = response.parsed_body
      expect(body["notes"].size).to eq(50)
      expect(body["has_more"]).to be true

      get results_note_view_path(view, page: 2), as: :json
      body2 = response.parsed_body
      expect(body2["notes"].size).to eq(5)
      expect(body2["has_more"]).to be false
    end

    it "returns dsl_errors for invalid operators" do
      view = create(:note_view, filter_query: "orphan:maybe")

      get results_note_view_path(view), as: :json

      body = response.parsed_body
      expect(body["dsl_errors"]).not_to be_empty
    end

    it "returns note properties and excerpt" do
      note = create_noted("Test Note", content: "Este e o conteudo da nota de teste")
      note.head_revision.update!(properties_data: {"status" => "draft"})
      view = create(:note_view)

      get results_note_view_path(view), as: :json

      note_data = response.parsed_body["notes"].find { |n| n["title"] == "Test Note" }
      expect(note_data["properties"]).to eq({"status" => "draft"})
      expect(note_data["excerpt"]).to be_present
      expect(note_data["slug"]).to be_present
    end
  end

  describe "authentication" do
    before { sign_out user }

    it "redirects unauthenticated requests" do
      get note_views_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
