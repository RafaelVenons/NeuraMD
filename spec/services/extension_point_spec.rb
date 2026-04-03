require "rails_helper"

RSpec.describe ExtensionPoint do
  let(:test_registry) do
    Class.new do
      include ExtensionPoint
      contract :apply
    end
  end

  let(:valid_handler) do
    Module.new { def self.apply(scope, value) = scope }
  end

  let(:invalid_handler) do
    Module.new { def self.nope = nil }
  end

  after do
    # Reset registry between tests
    test_registry.send(:instance_variable_set, :@registry, {})
    test_registry.send(:instance_variable_set, :@frozen, false)
  end

  describe ".register" do
    it "registers a handler that satisfies the contract" do
      test_registry.register(:foo, valid_handler)
      expect(test_registry.registered?(:foo)).to be true
    end

    it "raises ContractViolation for handler missing required methods" do
      expect {
        test_registry.register(:bad, invalid_handler)
      }.to raise_error(ExtensionPoint::ContractViolation, /apply/)
    end

    it "raises when registry is frozen" do
      test_registry.register(:foo, valid_handler)
      test_registry.freeze_registry!

      another = Module.new { def self.apply(scope, value) = scope }
      expect {
        test_registry.register(:bar, another)
      }.to raise_error(RuntimeError, /frozen/)
    end
  end

  describe ".lookup" do
    it "returns the registered handler" do
      test_registry.register(:foo, valid_handler)
      expect(test_registry.lookup(:foo)).to eq(valid_handler)
    end

    it "raises UnknownExtension for missing name" do
      expect {
        test_registry.lookup(:missing)
      }.to raise_error(ExtensionPoint::UnknownExtension, /missing/)
    end
  end

  describe ".lookup_safe" do
    it "returns the handler when found" do
      test_registry.register(:foo, valid_handler)
      expect(test_registry.lookup_safe(:foo)).to eq(valid_handler)
    end

    it "returns fallback when not found" do
      fallback = Module.new { def self.apply(scope, value) = scope }
      expect(test_registry.lookup_safe(:missing, fallback: fallback)).to eq(fallback)
    end

    it "returns nil when not found and no fallback" do
      expect(test_registry.lookup_safe(:missing)).to be_nil
    end
  end

  describe ".names" do
    it "returns all registered names" do
      test_registry.register(:alpha, valid_handler)
      another = Module.new { def self.apply(scope, value) = scope }
      test_registry.register(:beta, another)

      expect(test_registry.names).to contain_exactly("alpha", "beta")
    end

    it "returns frozen array" do
      expect(test_registry.names).to be_frozen
    end
  end

  describe ".registered?" do
    it "returns true for registered names" do
      test_registry.register(:foo, valid_handler)
      expect(test_registry.registered?(:foo)).to be true
    end

    it "returns false for unknown names" do
      expect(test_registry.registered?(:nope)).to be false
    end
  end

  describe ".freeze_registry!" do
    it "prevents further registration" do
      test_registry.freeze_registry!
      expect(test_registry.frozen_registry?).to be true
    end
  end

  describe ".required_methods" do
    it "returns the contract methods" do
      expect(test_registry.required_methods).to eq([:apply])
    end

    it "returns empty array when no contract defined" do
      bare = Class.new { include ExtensionPoint }
      expect(bare.required_methods).to eq([])
    end
  end

  describe ".default_handler" do
    it "sets and returns a default handler" do
      fallback = Module.new { def self.apply(scope, value) = "fallback" }
      test_registry.default_handler(fallback)
      expect(test_registry.default_handler).to eq(fallback)
    end

    it "returns nil when not set" do
      expect(test_registry.default_handler).to be_nil
    end
  end

  describe ".invoke_safe" do
    it "invokes the registered handler" do
      handler = Module.new { def self.apply(scope, value) = "result:#{value}" }
      test_registry.register(:foo, handler)

      expect(test_registry.invoke_safe(:foo, nil, "test")).to eq("result:test")
    end

    it "returns nil for unknown handler with no default" do
      expect(test_registry.invoke_safe(:missing, nil, "x")).to be_nil
    end

    it "falls back to default_handler when handler raises" do
      broken = Module.new { def self.apply(scope, value) = raise("boom") }
      fallback = Module.new { def self.apply(scope, value) = "safe" }
      test_registry.register(:broken, broken)
      test_registry.default_handler(fallback)

      expect(test_registry.invoke_safe(:broken, nil, "x")).to eq("safe")
    end

    it "returns nil when handler raises and no default set" do
      broken = Module.new { def self.apply(scope, value) = raise("boom") }
      test_registry.register(:broken, broken)

      expect(test_registry.invoke_safe(:broken, nil, "x")).to be_nil
    end

    it "uses default_handler for unknown names" do
      fallback = Module.new { def self.apply(scope, value) = "default" }
      test_registry.default_handler(fallback)

      expect(test_registry.invoke_safe(:missing, nil, "x")).to eq("default")
    end
  end
end
