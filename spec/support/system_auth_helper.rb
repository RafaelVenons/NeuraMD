module SystemAuthHelper
  def sign_in_via_ui(user, password: "password123")
    visit new_user_session_path
    fill_in "E-mail", with: user.email
    fill_in "Senha", with: password
    click_button "Entrar"

    expect(page).to have_current_path(graph_path, ignore_query: true, wait: 10)
    expect(page).to have_text(user.email, wait: 10)
  end
end

RSpec.configure do |config|
  config.include SystemAuthHelper, type: :system
end
