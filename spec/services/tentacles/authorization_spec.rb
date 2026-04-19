require "rails_helper"

RSpec.describe Tentacles::Authorization do
  describe ".enabled?" do
    it "is enabled in development" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      ENV.delete(described_class::ENABLED_ENV_KEY)
      expect(described_class).to be_enabled
    end

    it "is enabled in test" do
      expect(described_class).to be_enabled
    end

    it "is disabled in production by default" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      ENV.delete(described_class::ENABLED_ENV_KEY)
      expect(described_class).not_to be_enabled
    end

    it "is enabled in production when the env flag is set" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      ENV[described_class::ENABLED_ENV_KEY] = "1"
      expect(described_class).to be_enabled
    ensure
      ENV.delete(described_class::ENABLED_ENV_KEY)
    end
  end
end
