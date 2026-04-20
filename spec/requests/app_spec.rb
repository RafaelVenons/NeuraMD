require "rails_helper"

RSpec.describe "App shell", type: :request do
  describe "GET /app" do
    context "when signed out" do
      it "redirects to the sign-in page" do
        get "/app"
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when signed in" do
      let(:user) { create(:user) }
      before { sign_in user }

      it "renders the React shell entrypoint" do
        get "/app"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('id="app-root"')
        expect(response.body).to include("NeuraMD")
      end

      it "renders the same entrypoint for deep paths" do
        get "/app/graph"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('id="app-root"')

        get "/app/notes/some-slug"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('id="app-root"')
      end

      it "exposes the CSRF token to the shell" do
        get "/app"
        expect(response.body).to match(/<meta\s+name="csrf-token"/i)
      end
    end
  end
end
