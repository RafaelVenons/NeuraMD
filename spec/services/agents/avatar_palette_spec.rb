require "rails_helper"

RSpec.describe Agents::AvatarPalette do
  describe "ROLE_COLORS" do
    it "mirrors the frontend palette keys for agent roles" do
      expect(described_class::ROLE_COLORS).to include(
        "agente-gerente" => "#fbbf24",
        "agente-rubi" => "#ef4444",
        "agente-react" => "#38bdf8",
        "agente-uxui" => "#c084fc",
        "agente-especialista-neuramd" => "#60a5fa"
      )
    end

    it "is frozen so callers cannot mutate the palette" do
      expect(described_class::ROLE_COLORS).to be_frozen
    end
  end

  describe ".default_color_for" do
    it "returns the color of the first matching role tag" do
      expect(described_class.default_color_for(%w[agente-team agente-rubi])).to eq("#ef4444")
    end

    it "ignores non-role tags and non-agente prefixes" do
      expect(described_class.default_color_for(%w[grafo plan-estrutura agente-gerente])).to eq("#fbbf24")
    end

    it "falls back to DEFAULT_COLOR when no role tag matches" do
      expect(described_class.default_color_for(%w[agente-team grafo])).to eq(described_class::DEFAULT_COLOR)
    end

    it "returns DEFAULT_COLOR for an empty tag list" do
      expect(described_class.default_color_for([])).to eq(described_class::DEFAULT_COLOR)
    end

    it "accepts an Enumerable, not just Array" do
      expect(described_class.default_color_for(Set["agente-team", "agente-uxui"])).to eq("#c084fc")
    end
  end

  describe "HATS" do
    it "starts with the base catalog agreed in the briefing" do
      expect(described_class::HATS).to eq(%w[none cartola chef])
    end

    it "includes DEFAULT_HAT" do
      expect(described_class::HATS).to include(described_class::DEFAULT_HAT)
    end
  end

  describe "VARIANTS" do
    it "is a bounded allow-list starting with clawd-v1" do
      expect(described_class::VARIANTS).to eq(%w[clawd-v1])
    end

    it "includes DEFAULT_VARIANT" do
      expect(described_class::VARIANTS).to include(described_class::DEFAULT_VARIANT)
    end

    it "is frozen" do
      expect(described_class::VARIANTS).to be_frozen
    end
  end

  describe "DEFAULT_VARIANT" do
    it "is clawd-v1 (reserved for future variants)" do
      expect(described_class::DEFAULT_VARIANT).to eq("clawd-v1")
    end
  end
end
