module Agents
  module AvatarPalette
    ROLE_COLORS = {
      "agente-gerente" => "#fbbf24",
      "agente-agenda" => "#f97316",
      "agente-cicd" => "#4ade80",
      "agente-devops" => "#10b981",
      "agente-gw" => "#22d3ee",
      "agente-qa" => "#a78bfa",
      "agente-rubi" => "#ef4444",
      "agente-react" => "#38bdf8",
      "agente-uxui" => "#c084fc",
      "agente-especialista-neuramd" => "#60a5fa",
      "agente-secinfo" => "#f87171",
      "agente-redteam" => "#dc2626",
      "agente-supply-chain" => "#d97706",
      "agente-team-raiz" => "#fb923c",
      "agente-python" => "#eab308",
      "agente-telegram" => "#0ea5e9",
      "agente-dev-catarata" => "#06b6d4",
      "agente-dev-maple" => "#84cc16",
      "agente-dev-sage" => "#14b8a6",
      "agente-dev-shopai" => "#ec4899",
      "agente-sage-worker" => "#0891b2"
    }.freeze

    DEFAULT_COLOR = "#b4a7d6".freeze

    HATS = %w[none cartola chef].freeze
    DEFAULT_HAT = "none".freeze

    DEFAULT_VARIANT = "clawd-v1".freeze

    def self.default_color_for(tag_names)
      tag_names.each do |name|
        color = ROLE_COLORS[name]
        return color if color
      end
      DEFAULT_COLOR
    end
  end
end
