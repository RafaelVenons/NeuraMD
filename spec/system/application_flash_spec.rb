require "rails_helper"

RSpec.describe "Application flash", type: :system do
  it "auto-dismisses the welcome notice after sign in" do
    user = create(:user)

    visit new_user_session_path

    fill_in "E-mail", with: user.email
    fill_in "Senha", with: "password123"
    click_button "Entrar"

    expect(page).to have_css(".nm-app-flash__message--notice", text: "Bem-vindo!", wait: 5)
    expect(page).not_to have_css(".nm-app-flash__message--notice", wait: 5)
  end
end
