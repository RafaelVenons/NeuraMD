require "rails_helper"

RSpec.describe "Authentication", type: :request do
  describe "GET /users/sign_in" do
    it "returns http success" do
      get new_user_session_path
      expect(response).to have_http_status(:ok)
    end

    it "renders the auth layout (not the main application layout)" do
      get new_user_session_path
      expect(response.body).to include("NeuraMD")
      expect(response.body).not_to include("<nav") # auth layout has no navbar
    end
  end

  describe "GET /users/sign_up" do
    it "returns http success" do
      get new_user_registration_path
      expect(response).to have_http_status(:ok)
    end

    it "contains the registration form" do
      get new_user_registration_path
      expect(response.body).to include('action="/users"')
        .or include('type="email"')
    end
  end

  describe "unauthenticated redirect" do
    it "redirects to login when accessing notes without session" do
      get notes_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "sets a flash alert with Portuguese message after redirect" do
      get notes_path
      follow_redirect!
      expect(response.body).to include("entrar")
    end
  end

  describe "POST /users/sign_in" do
    let!(:user) { create(:user) }

    it "signs in with valid credentials" do
      post user_session_path, params: {
        user: { email: user.email, password: "password123" }
      }
      expect(response).to redirect_to(graph_path)
    end

    it "rejects invalid credentials and shows Portuguese error" do
      post user_session_path, params: {
        user: { email: user.email, password: "wrong" }
      }
      # Devise + Turbo re-renders with 422 (no redirect)
      expect(response).to have_http_status(:unprocessable_content)
        .or have_http_status(:ok)
        .or redirect_to(new_user_session_path)
      # Check flash is set with pt-BR message
      expect(flash[:alert]).to include("inválidos").or include("inválid")
    end
  end
end
