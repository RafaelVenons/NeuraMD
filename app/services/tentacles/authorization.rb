module Tentacles
  module Authorization
    ENABLED_ENV_KEY = "NEURAMD_TENTACLES_ENABLED".freeze

    def self.enabled?
      return true if ENV[ENABLED_ENV_KEY] == "1"
      return true if Rails.env.development? || Rails.env.test?
      false
    end
  end
end
