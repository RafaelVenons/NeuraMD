# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpAccessToken do
  describe ".issue!" do
    it "creates a token, returns the plaintext, and stores only the hash" do
      result = described_class.issue!(name: "test", scopes: %w[read])

      expect(result.plaintext).to be_a(String)
      expect(result.plaintext.length).to be >= 32
      expect(result.record).to be_persisted
      expect(result.record.token_hash).not_to eq(result.plaintext)
      expect(result.record.token_hash).to eq(described_class.hash_for(result.plaintext))
      expect(result.record.scopes).to eq(%w[read])
    end

    it "rejects unknown scopes" do
      expect {
        described_class.issue!(name: "bad", scopes: %w[read superuser])
      }.to raise_error(ActiveRecord::RecordInvalid, /unknown scope/i)
    end

    it "requires a name" do
      expect {
        described_class.issue!(name: "", scopes: %w[read])
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe ".authenticate" do
    let!(:issued) { described_class.issue!(name: "live", scopes: %w[read write]) }

    it "returns the token for a valid plaintext" do
      found = described_class.authenticate(issued.plaintext)
      expect(found).to eq(issued.record)
    end

    it "returns nil for unknown plaintext" do
      expect(described_class.authenticate("nope")).to be_nil
    end

    it "returns nil for blank input" do
      expect(described_class.authenticate(nil)).to be_nil
      expect(described_class.authenticate("")).to be_nil
    end

    it "returns nil for revoked tokens" do
      issued.record.update!(revoked_at: Time.current)
      expect(described_class.authenticate(issued.plaintext)).to be_nil
    end
  end

  describe "#scope?" do
    let(:token) { described_class.issue!(name: "rw", scopes: %w[read write]).record }

    it "is true for granted scopes" do
      expect(token.scope?(:read)).to be true
      expect(token.scope?("write")).to be true
    end

    it "is false for missing scopes" do
      expect(token.scope?(:tentacle)).to be false
    end
  end

  describe "#touch_used!" do
    let(:token) { described_class.issue!(name: "t", scopes: %w[read]).record }

    it "updates last_used_at without touching updated_at" do
      original_updated = 2.days.ago
      token.update_columns(updated_at: original_updated, last_used_at: nil)

      freeze_time do
        token.touch_used!
        token.reload
        expect(token.last_used_at).to be_within(1.second).of(Time.current)
        expect(token.updated_at).to be_within(1.second).of(original_updated)
      end
    end
  end
end
