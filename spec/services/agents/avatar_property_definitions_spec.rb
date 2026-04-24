require "rails_helper"

RSpec.describe Agents::AvatarPropertyDefinitions do
  describe ".ensure!" do
    it "creates the three avatar PDs with the expected shape when none exist" do
      described_class.ensure!

      color = PropertyDefinition.find_by(key: "avatar_color")
      expect(color).to be_present
      expect(color.value_type).to eq("text")
      expect(color.system).to be true
      expect(color.archived).to be false
      expect(color.config.fetch("pattern")).to eq(described_class::HEX_COLOR_PATTERN)

      hat = PropertyDefinition.find_by(key: "avatar_hat")
      expect(hat).to be_present
      expect(hat.value_type).to eq("enum")
      expect(hat.system).to be true
      expect(hat.config.fetch("options")).to eq(Agents::AvatarPalette::HATS)

      variant = PropertyDefinition.find_by(key: "avatar_variant")
      expect(variant).to be_present
      expect(variant.value_type).to eq("enum")
      expect(variant.system).to be true
      expect(variant.config.fetch("options")).to eq(Agents::AvatarPalette::VARIANTS)
    end

    it "is idempotent — calling twice produces no duplicates and does not raise" do
      described_class.ensure!
      expect { described_class.ensure! }.not_to raise_error
      expect(PropertyDefinition.where(key: %w[avatar_color avatar_hat avatar_variant]).count).to eq(3)
    end

    it "upgrades a pre-existing system PD with a stale shape to the expected shape" do
      PropertyDefinition.create!(
        key: "avatar_hat",
        value_type: "text",
        system: true,
        archived: true,
        label: "legacy system hat",
        config: {}
      )

      described_class.ensure!

      pd = PropertyDefinition.find_by!(key: "avatar_hat")
      expect(pd.value_type).to eq("enum")
      expect(pd.system).to be true
      expect(pd.archived).to be false
      expect(pd.config.fetch("options")).to eq(Agents::AvatarPalette::HATS)
      expect(pd.label).to eq("Chapéu do avatar")
    end

    # Guard against round-3 finding #2: destructive hijack of user-created PDs.
    # If an environment has a `system: false` PD with the same key (someone
    # created a custom "avatar_color" field via the PD API before the deploy),
    # silently overwriting would change the meaning of existing stored values
    # without rollback. Fail loudly and require operator action instead.
    it "raises when a user-owned (system: false) PD exists with the same key" do
      PropertyDefinition.create!(
        key: "avatar_color",
        value_type: "text",
        system: false,
        archived: false,
        config: {}
      )

      expect { described_class.ensure! }
        .to raise_error(described_class::UserOwnedCollisionError, /avatar_color.*system-owned/i)
    end

    it "raises for multiple colliding user-owned keys at once" do
      PropertyDefinition.create!(key: "avatar_hat", value_type: "text", system: false, config: {})
      PropertyDefinition.create!(key: "avatar_variant", value_type: "text", system: false, config: {})

      expect { described_class.ensure! }
        .to raise_error(described_class::UserOwnedCollisionError, /avatar_hat|avatar_variant/)
    end

    it "does not create any rows when a collision is detected (all-or-nothing)" do
      PropertyDefinition.create!(key: "avatar_color", value_type: "text", system: false, config: {})

      expect { described_class.ensure! rescue nil }
        .not_to change { PropertyDefinition.where(key: %w[avatar_hat avatar_variant]).count }
    end
  end

  # End-to-end guard for round-3 finding #3: `avatar_color` must be validated
  # at the write path, not only at serialization. Hex pattern goes in
  # PropertyDefinition.config["pattern"] and Properties::Types::Text enforces.
  describe "write-path validation after ensure!" do
    before { described_class.ensure! }

    let(:note) { create(:note, :with_head_revision, title: "Agent") }

    it "records _errors for avatar_color that is not a hex value (strict: false)" do
      Properties::SetService.call(
        note: note,
        changes: {"avatar_color" => "banana"},
        strict: false
      )

      note.reload
      expect(note.head_revision.properties_data.fetch("_errors")).to have_key("avatar_color")
    end

    it "raises ValidationError for bad avatar_color (strict: true)" do
      expect {
        Properties::SetService.call(
          note: note,
          changes: {"avatar_color" => "not-a-color"},
          strict: true
        )
      }.to raise_error(Properties::SetService::ValidationError, /avatar_color/)
    end

    it "accepts #rrggbb and #rgb values at write time" do
      expect {
        Properties::SetService.call(
          note: note,
          changes: {"avatar_color" => "#1a2b3c"},
          strict: true
        )
      }.not_to raise_error

      note.reload
      expect(note.head_revision.properties_data["avatar_color"]).to eq("#1a2b3c")
    end
  end
end
