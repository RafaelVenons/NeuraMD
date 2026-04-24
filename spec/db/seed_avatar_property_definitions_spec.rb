require "rails_helper"
require Rails.root.join("db/migrate/20260424005046_seed_avatar_property_definitions.rb")

RSpec.describe SeedAvatarPropertyDefinitions do
  # DatabaseCleaner truncates PropertyDefinitions between specs, so we re-run the
  # migration's #up inline and assert the shape it produced. Also guarantees
  # idempotency (running twice does not raise or duplicate).
  let(:migration) { described_class.new }

  def run_up
    ActiveRecord::Migration.suppress_messages { migration.up }
  end

  it "creates avatar_color as a system text PD" do
    run_up
    pd = PropertyDefinition.find_by(key: "avatar_color")
    expect(pd).to be_present
    expect(pd.value_type).to eq("text")
    expect(pd.system).to be true
  end

  it "creates avatar_hat as a system enum PD whose options match the frozen allow-list" do
    run_up
    pd = PropertyDefinition.find_by(key: "avatar_hat")
    expect(pd).to be_present
    expect(pd.value_type).to eq("enum")
    expect(pd.system).to be true
    expect(pd.config.fetch("options")).to eq(described_class::ALLOWED_HATS)
    expect(pd.config.fetch("options")).to eq(Agents::AvatarPalette::HATS)
  end

  it "creates avatar_variant as a system text PD" do
    run_up
    pd = PropertyDefinition.find_by(key: "avatar_variant")
    expect(pd).to be_present
    expect(pd.value_type).to eq("text")
    expect(pd.system).to be true
  end

  it "is idempotent — running up twice does not duplicate PDs or raise" do
    run_up
    expect { run_up }.not_to raise_error
    expect(PropertyDefinition.where(key: %w[avatar_color avatar_hat avatar_variant]).count).to eq(3)
  end
end
