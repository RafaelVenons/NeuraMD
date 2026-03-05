require "rails_helper"

RSpec.describe "Devise i18n (pt-BR)" do
  before { I18n.locale = :"pt-BR" }
  after  { I18n.locale = I18n.default_locale }

  it "translates unauthenticated failure message" do
    expect(I18n.t("devise.failure.unauthenticated"))
      .not_to start_with("translation missing")
    expect(I18n.t("devise.failure.unauthenticated"))
      .to include("entrar")
  end

  it "translates invalid credentials message" do
    expect(I18n.t("devise.failure.invalid"))
      .not_to start_with("translation missing")
  end

  it "translates signed_in message" do
    expect(I18n.t("devise.sessions.signed_in"))
      .not_to start_with("translation missing")
  end

  it "translates signed_out message" do
    expect(I18n.t("devise.sessions.signed_out"))
      .not_to start_with("translation missing")
  end

  it "translates registration signed_up message" do
    expect(I18n.t("devise.registrations.signed_up"))
      .not_to start_with("translation missing")
  end

  it "translates not_saved error (singular)" do
    msg = I18n.t("errors.messages.not_saved", count: 1, resource: "nota")
    expect(msg).not_to start_with("translation missing")
    expect(msg).to include("1 erro")
  end

  it "translates not_saved error (plural)" do
    msg = I18n.t("errors.messages.not_saved", count: 3, resource: "nota")
    expect(msg).not_to start_with("translation missing")
    expect(msg).to include("3 erros")
  end
end
