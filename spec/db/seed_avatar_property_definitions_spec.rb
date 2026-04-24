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

  # Guard against environment skew flagged by adversarial review: a
  # pre-existing (user-created) PropertyDefinition with a conflicting shape
  # must be corrected to the system-owned shape, not silently preserved.
  it "overwrites a pre-existing avatar_hat that has the wrong value_type/config/system flag" do
    PropertyDefinition.create!(
      key: "avatar_hat",
      value_type: "text",
      system: false,
      archived: true,
      label: "legacy hat",
      config: {}
    )

    run_up

    pd = PropertyDefinition.find_by!(key: "avatar_hat")
    expect(pd.value_type).to eq("enum")
    expect(pd.config.fetch("options")).to eq(described_class::ALLOWED_HATS)
    expect(pd.system).to be true
    expect(pd.archived).to be false
    expect(pd.label).to eq("Chapéu do avatar")
  end

  it "overwrites a pre-existing avatar_color with wrong system flag" do
    PropertyDefinition.create!(
      key: "avatar_color",
      value_type: "text",
      system: false,
      archived: false,
      config: {"stale" => true}
    )

    run_up

    pd = PropertyDefinition.find_by!(key: "avatar_color")
    expect(pd.value_type).to eq("text")
    expect(pd.system).to be true
    expect(pd.config).to eq({})
  end

  it "does not duplicate rows when a pre-existing conflicting PD is corrected" do
    PropertyDefinition.create!(key: "avatar_variant", value_type: "long_text", system: false, config: {})
    run_up
    expect(PropertyDefinition.where(key: "avatar_variant").count).to eq(1)
  end
end
