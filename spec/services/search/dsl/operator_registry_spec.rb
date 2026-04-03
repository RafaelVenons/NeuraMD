require "rails_helper"

RSpec.describe Search::Dsl::OperatorRegistry do
  let(:expected_operators) do
    %w[tag alias prop kind status has link linkedfrom orphan deadend created updated]
  end

  describe "built-in registrations" do
    it "has all 12 operators registered" do
      expect(described_class.names).to match_array(expected_operators)
    end

    it "each handler implements .apply" do
      expected_operators.each do |op|
        handler = described_class.lookup(op)
        expect(handler).to respond_to(:apply), "#{op} handler does not implement .apply"
      end
    end
  end

  describe "operators with validation" do
    it "prop validates = presence" do
      handler = described_class.lookup(:prop)
      expect(handler.validate("status=done")).to be_nil
      expect(handler.validate("nope")).to be_a(String)
    end

    it "has validates known values" do
      handler = described_class.lookup(:has)
      expect(handler.validate("asset")).to be_nil
      expect(handler.validate("unknown")).to be_a(String)
    end

    it "orphan validates boolean values" do
      handler = described_class.lookup(:orphan)
      expect(handler.validate("true")).to be_nil
      expect(handler.validate("nope")).to be_a(String)
    end

    it "deadend validates boolean values" do
      handler = described_class.lookup(:deadend)
      expect(handler.validate("false")).to be_nil
      expect(handler.validate("nope")).to be_a(String)
    end

    it "created validates date format" do
      handler = described_class.lookup(:created)
      expect(handler.validate(">2024-01")).to be_nil
      expect(handler.validate("nope")).to be_a(String)
    end

    it "updated validates date format" do
      handler = described_class.lookup(:updated)
      expect(handler.validate("<7d")).to be_nil
      expect(handler.validate("nope")).to be_a(String)
    end
  end

  describe "contract enforcement" do
    it "rejects handler without .apply" do
      bad = Module.new { def self.nope = nil }
      expect {
        described_class.register(:broken, bad)
      }.to raise_error(ExtensionPoint::ContractViolation)
    end
  end

  describe ".registered?" do
    it "returns true for known operators" do
      expect(described_class.registered?(:tag)).to be true
    end

    it "returns false for unknown operators" do
      expect(described_class.registered?(:nonexistent)).to be false
    end
  end
end
