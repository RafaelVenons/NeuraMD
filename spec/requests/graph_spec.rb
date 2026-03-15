require "rails_helper"

RSpec.describe "Graph API", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /api/graph" do
    it "returns nodes and edges for active notes only" do
      source = create(:note, :with_head_revision, title: "Origem")
      target = create(:note, :with_head_revision, title: "Destino")
      deleted = create(:note, :with_head_revision, :deleted, title: "Arquivada")

      link = create(
        :note_link,
        src_note: source,
        dst_note: target,
        created_in_revision: source.head_revision,
        hier_role: "target_is_parent"
      )
      urgent = create(:tag, name: "Urgente", color_hex: "#ef4444")
      link.tags << urgent

      create(
        :note_link,
        src_note: source,
        dst_note: deleted,
        created_in_revision: source.head_revision,
        hier_role: "same_level"
      )

      get "/api/graph"

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body

      expect(payload["meta"]).to include("node_count" => 2, "edge_count" => 1)

      nodes = payload["nodes"]
      edges = payload["edges"]

      expect(nodes.map { |node| node["title"] }).to contain_exactly("Origem", "Destino")
      expect(nodes.find { |node| node["title"] == "Origem" }).to include(
        "outgoing_count" => 1,
        "incoming_count" => 0,
        "degree" => 1
      )
      expect(nodes.find { |node| node["title"] == "Destino" }).to include(
        "outgoing_count" => 0,
        "incoming_count" => 1,
        "degree" => 1
      )

      expect(edges).to contain_exactly(
        include(
          "source" => source.id,
          "target" => target.id,
          "hier_role" => "target_is_parent",
          "role_label" => "father",
          "tags" => [include("name" => "urgente", "color_hex" => "#ef4444")]
        )
      )
    end

    it "returns an empty graph when there are no notes" do
      get "/api/graph"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        "nodes" => [],
        "edges" => [],
        "meta" => {"node_count" => 0, "edge_count" => 0}
      )
    end
  end
end
