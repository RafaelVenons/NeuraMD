require "rails_helper"

RSpec.describe "Graph page", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /graph" do
    it "renders the graph shell and data endpoint wiring" do
      get graph_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Grafo das notas")
      expect(response.body).to include('data-controller="graph-view"')
      expect(response.body).to include(%(data-graph-view-data-url-value="#{api_graph_path}"))
    end
  end
end
