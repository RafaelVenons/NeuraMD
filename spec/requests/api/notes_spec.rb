require "rails_helper"

RSpec.describe "API notes", type: :request do
  let(:user) { create(:user) }

  def build_note(title:, body: "# Body\n\nSome content.", tags: [])
    create(:note, title: title).tap do |n|
      rev = create(:note_revision, note: n, content_markdown: body)
      n.update_columns(head_revision_id: rev.id)
      tags.each do |tag_name|
        tag = Tag.find_or_create_by!(name: tag_name)
        NoteTag.find_or_create_by!(note: n, tag: tag)
      end
    end
  end

  describe "GET /api/notes/:slug" do
    it "returns 401 in the shared envelope when signed out" do
      note = build_note(title: "Anon")

      get "/api/notes/#{note.slug}", headers: {"ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("code" => "unauthorized")
    end

    it "returns the note, head revision content and metadata" do
      sign_in user
      note = build_note(title: "My Note", body: "# Heading\n\nBody.", tags: ["plan", "plan-estrutura"])
      note.note_aliases.create!(name: "my-alias")

      get "/api/notes/#{note.slug}"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["note"]).to include("id" => note.id, "slug" => note.slug, "title" => "My Note")
      expect(body["revision"]["content_markdown"]).to eq("# Heading\n\nBody.")
      expect(body["tags"]).to contain_exactly(
        a_hash_including("name" => "plan"),
        a_hash_including("name" => "plan-estrutura")
      )
      expect(body["aliases"]).to contain_exactly("my-alias")
      expect(body["properties"]).to eq({})
    end

    it "includes active property definitions in the payload" do
      sign_in user
      note = build_note(title: "With Props")
      PropertyDefinition.create!(key: "priority", value_type: "enum",
        label: "Prioridade", config: {"options" => ["low", "med", "high"]}, position: 1)
      PropertyDefinition.create!(key: "due_on", value_type: "date", label: "Prazo", position: 2)
      PropertyDefinition.create!(key: "archived_key", value_type: "text", archived: true, position: 3)

      get "/api/notes/#{note.slug}"

      expect(response).to have_http_status(:ok)
      keys = response.parsed_body["property_definitions"].map { |d| d["key"] }
      expect(keys).to contain_exactly("priority", "due_on")
    end

    it "returns a standardized 404 envelope for unknown slugs" do
      sign_in user
      get "/api/notes/does-not-exist"

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to include("code" => "not_found")
    end

    it "resolves slug redirects by pointing at the canonical slug" do
      sign_in user
      note = build_note(title: "Renamed")
      SlugRedirect.create!(note: note, slug: "old-slug")

      get "/api/notes/old-slug"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["note"]["slug"]).to eq(note.slug)
    end
  end

  describe "POST /api/notes/:slug/draft" do
    it "returns 401 envelope when signed out" do
      note = build_note(title: "Anon")

      post "/api/notes/#{note.slug}/draft",
        params: {content_markdown: "hi"}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("code" => "unauthorized")
    end

    it "persists a draft revision and returns saved=true" do
      sign_in user
      note = build_note(title: "Draft Target", body: "original")

      post "/api/notes/#{note.slug}/draft",
        params: {content_markdown: "updated body"}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json"}

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["saved"]).to eq(true)
      expect(body["kind"]).to eq("draft")
      expect(note.note_revisions.where(revision_kind: "draft").first.content_markdown).to eq("updated body")
    end

    it "returns a standardized 404 envelope for unknown slugs" do
      sign_in user

      post "/api/notes/missing/draft",
        params: {content_markdown: "hi"}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json"}

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body["error"]).to include("code" => "not_found")
    end
  end

  describe "PATCH /api/notes/:slug/properties" do
    let!(:priority_def) do
      PropertyDefinition.create!(key: "priority", value_type: "enum",
        label: "Prioridade", config: {"options" => ["low", "med", "high"]}, position: 1)
    end

    it "returns 401 envelope when signed out" do
      note = build_note(title: "Anon Props")

      patch "/api/notes/#{note.slug}/properties",
        params: {changes: {priority: "high"}}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("code" => "unauthorized")
    end

    it "applies property changes and returns the new map" do
      sign_in user
      note = build_note(title: "With Props")

      patch "/api/notes/#{note.slug}/properties",
        params: {changes: {priority: "high"}}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json"}

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["properties"]).to eq({"priority" => "high"})
      expect(body["properties_errors"]).to eq({})
    end

    it "returns invalid_params envelope for unknown keys" do
      sign_in user
      note = build_note(title: "With Props")

      patch "/api/notes/#{note.slug}/properties",
        params: {changes: {bogus: "x"}}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("code" => "unknown_property_key")
    end

    it "returns 404 envelope for unknown notes" do
      sign_in user

      patch "/api/notes/missing/properties",
        params: {changes: {priority: "high"}}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json"}

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/notes/:slug/tags" do
    it "returns 401 envelope when signed out" do
      note = build_note(title: "Anon Tag")

      post "/api/notes/#{note.slug}/tags",
        params: {name: "plan"}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("code" => "unauthorized")
    end

    it "attaches an existing tag and returns the updated tag list" do
      sign_in user
      note = build_note(title: "Attach Target")
      Tag.create!(name: "plan", tag_scope: "note", color_hex: "#ff0000")

      post "/api/notes/#{note.slug}/tags",
        params: {name: "plan"}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json"}

      expect(response).to have_http_status(:ok)
      names = response.parsed_body["tags"].map { |t| t["name"] }
      expect(names).to include("plan")
      expect(note.reload.tags.map(&:name)).to include("plan")
    end

    it "creates the tag on demand when it does not exist" do
      sign_in user
      note = build_note(title: "Create On Demand")

      post "/api/notes/#{note.slug}/tags",
        params: {name: "Brand New", color_hex: "#112233"}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json"}

      expect(response).to have_http_status(:ok)
      tag = Tag.find_by(name: "brand new")
      expect(tag).to be_present
      expect(tag.color_hex).to eq("#112233")
      expect(note.reload.tags).to include(tag)
    end

    it "is idempotent when the tag is already attached" do
      sign_in user
      note = build_note(title: "Idempotent", tags: ["plan"])

      expect {
        post "/api/notes/#{note.slug}/tags",
          params: {name: "plan"}.to_json,
          headers: {"CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json"}
      }.not_to change { note.tags.count }

      expect(response).to have_http_status(:ok)
    end

    it "rejects blank tag names with invalid_params" do
      sign_in user
      note = build_note(title: "Blank Tag")

      post "/api/notes/#{note.slug}/tags",
        params: {name: "   "}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("code" => "invalid_params")
    end

    it "promotes a link-only tag to both when attaching it to a note" do
      sign_in user
      note = build_note(title: "Promote Link Tag")
      link_tag = Tag.create!(name: "legacy", tag_scope: "link", color_hex: "#aa0000")

      post "/api/notes/#{note.slug}/tags",
        params: {name: "legacy"}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json"}

      expect(response).to have_http_status(:ok)
      names = response.parsed_body["tags"].map { |t| t["name"] }
      expect(names).to include("legacy")
      expect(link_tag.reload.tag_scope).to eq("both")
      expect(note.reload.tags.map(&:name)).to include("legacy")
    end

    it "returns 404 envelope for unknown notes" do
      sign_in user

      post "/api/notes/missing/tags",
        params: {name: "plan"}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json"}

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/notes/:slug/tags/:tag_id" do
    it "detaches the tag and returns the remaining list" do
      sign_in user
      note = build_note(title: "Detach", tags: ["plan", "spec"])
      plan = Tag.find_by!(name: "plan")

      delete "/api/notes/#{note.slug}/tags/#{plan.id}",
        headers: {"ACCEPT" => "application/json"}

      expect(response).to have_http_status(:ok)
      names = response.parsed_body["tags"].map { |t| t["name"] }
      expect(names).to contain_exactly("spec")
      expect(note.reload.tags.map(&:name)).not_to include("plan")
    end

    it "returns 404 envelope when the tag id does not exist" do
      sign_in user
      note = build_note(title: "Missing Tag")

      delete "/api/notes/#{note.slug}/tags/999999",
        headers: {"ACCEPT" => "application/json"}

      expect(response).to have_http_status(:not_found)
    end

    it "returns 401 envelope when signed out" do
      note = build_note(title: "Anon Detach", tags: ["plan"])
      plan = Tag.find_by!(name: "plan")

      delete "/api/notes/#{note.slug}/tags/#{plan.id}",
        headers: {"ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/tags" do
    it "lists note-scope tags ordered by name" do
      sign_in user
      Tag.create!(name: "gamma", tag_scope: "note", color_hex: "#111111")
      Tag.create!(name: "alpha", tag_scope: "both", color_hex: "#222222")
      Tag.create!(name: "link-only", tag_scope: "link")

      get "/api/tags"

      expect(response).to have_http_status(:ok)
      names = response.parsed_body["tags"].map { |t| t["name"] }
      expect(names).to eq(%w[alpha gamma])
    end

    it "returns 401 envelope when signed out" do
      get "/api/tags", headers: {"ACCEPT" => "application/json"}
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/notes/:slug/checkpoint" do
    it "persists a checkpoint revision and returns metadata" do
      sign_in user
      note = build_note(title: "Checkpoint", body: "original body")

      post "/api/notes/#{note.slug}/checkpoint",
        params: {content_markdown: "brand new body"}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json"}

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["saved"]).to eq(true)
      expect(body["kind"]).to eq("checkpoint")
      expect(body["revision_id"]).to be_present
      checkpoint = note.note_revisions.where(revision_kind: "checkpoint").order(created_at: :desc).first
      expect(checkpoint.content_markdown).to eq("brand new body")
    end

    it "returns 401 envelope when signed out" do
      note = build_note(title: "Anon Checkpoint")

      post "/api/notes/#{note.slug}/checkpoint",
        params: {content_markdown: "hi"}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 404 envelope for unknown notes" do
      sign_in user

      post "/api/notes/missing/checkpoint",
        params: {content_markdown: "hi"}.to_json,
        headers: {"CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json"}

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/notes/:slug/revisions" do
    it "lists checkpoints newest first with is_head flag" do
      sign_in user
      note = build_note(title: "History")
      rev1 = create(:note_revision, note: note, content_markdown: "v1", revision_kind: :checkpoint, created_at: 2.hours.ago)
      rev2 = create(:note_revision, note: note, content_markdown: "v2", revision_kind: :checkpoint, created_at: 1.hour.ago)
      create(:note_revision, note: note, content_markdown: "draft body", revision_kind: :draft)
      note.update_columns(head_revision_id: rev2.id)

      get "/api/notes/#{note.slug}/revisions"

      expect(response).to have_http_status(:ok)
      revisions = response.parsed_body["revisions"]
      ids = revisions.map { |r| r["id"] }
      expect(ids.index(rev2.id)).to be < ids.index(rev1.id)
      expect(revisions.find { |r| r["id"] == rev2.id }["is_head"]).to be true
      expect(revisions.find { |r| r["id"] == rev1.id }["is_head"]).to be false
      kinds = note.note_revisions.where(id: ids).pluck(:revision_kind).uniq
      expect(kinds).to eq(["checkpoint"])
    end

    it "returns 401 envelope when signed out" do
      note = build_note(title: "Anon History")

      get "/api/notes/#{note.slug}/revisions", headers: {"ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/notes/:slug/revisions/:revision_id/restore" do
    it "restores a checkpoint and returns the new revision id" do
      sign_in user
      note = build_note(title: "Restore")
      rev_old = create(:note_revision, note: note, content_markdown: "old body", revision_kind: :checkpoint, created_at: 2.hours.ago)
      rev_head = create(:note_revision, note: note, content_markdown: "current body", revision_kind: :checkpoint, created_at: 1.hour.ago)
      note.update_columns(head_revision_id: rev_head.id)

      post "/api/notes/#{note.slug}/revisions/#{rev_old.id}/restore",
        headers: {"ACCEPT" => "application/json"}

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["saved"]).to eq(true)
      new_rev = note.note_revisions.find(body["revision_id"])
      expect(new_rev.content_markdown).to eq("old body")
    end

    it "returns 404 envelope for unknown revisions" do
      sign_in user
      note = build_note(title: "No Such Revision")

      post "/api/notes/#{note.slug}/revisions/00000000-0000-0000-0000-000000000000/restore",
        headers: {"ACCEPT" => "application/json"}

      expect(response).to have_http_status(:not_found)
    end

    it "returns 401 envelope when signed out" do
      note = build_note(title: "Anon Restore")
      rev = create(:note_revision, note: note, content_markdown: "x", revision_kind: :checkpoint)

      post "/api/notes/#{note.slug}/revisions/#{rev.id}/restore",
        headers: {"ACCEPT" => "application/json"}

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
