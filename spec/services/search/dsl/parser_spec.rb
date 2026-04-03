require "rails_helper"

RSpec.describe Search::Dsl::Parser do
  describe ".call" do
    it "parses a single operator" do
      result = described_class.call("tag:neurociencia")
      expect(result.tokens.size).to eq(1)
      expect(result.tokens.first.operator).to eq(:tag)
      expect(result.tokens.first.value).to eq("neurociencia")
      expect(result.text).to eq("")
    end

    it "parses multiple operators" do
      result = described_class.call("tag:neuro status:draft")
      expect(result.tokens.size).to eq(2)
      expect(result.tokens.map(&:operator)).to eq([:tag, :status])
      expect(result.tokens.map(&:value)).to eq(%w[neuro draft])
      expect(result.text).to eq("")
    end

    it "separates operators from free text" do
      result = described_class.call("tag:neuro algum texto livre")
      expect(result.tokens.size).to eq(1)
      expect(result.tokens.first.operator).to eq(:tag)
      expect(result.text).to eq("algum texto livre")
    end

    it "preserves free text when no operators present" do
      result = described_class.call("busca normal de texto")
      expect(result.tokens).to be_empty
      expect(result.text).to eq("busca normal de texto")
    end

    it "ignores unknown operator prefixes as plain text" do
      result = described_class.call("foo:bar baz")
      expect(result.tokens).to be_empty
      expect(result.text).to eq("foo:bar baz")
    end

    it "is case-insensitive for operator names" do
      result = described_class.call("TAG:neuro Status:draft")
      expect(result.tokens.size).to eq(2)
      expect(result.tokens.map(&:operator)).to eq([:tag, :status])
    end

    it "records position of each token" do
      result = described_class.call("tag:neuro status:draft")
      expect(result.tokens.first.position).to eq(0)
      expect(result.tokens.last.position).to eq(10)
    end

    it "stores raw matched text in each token" do
      result = described_class.call("TAG:neuro")
      expect(result.tokens.first.raw).to eq("TAG:neuro")
    end

    context "operator validation" do
      it "rejects orphan with invalid value" do
        result = described_class.call("orphan:maybe")
        expect(result.tokens).to be_empty
        expect(result.errors.size).to eq(1)
        expect(result.errors.first[:operator]).to eq(:orphan)
        expect(result.text).to eq("orphan:maybe")
      end

      it "accepts orphan:true" do
        result = described_class.call("orphan:true")
        expect(result.tokens.size).to eq(1)
        expect(result.errors).to be_empty
      end

      it "accepts deadend:false" do
        result = described_class.call("deadend:false")
        expect(result.tokens.size).to eq(1)
        expect(result.errors).to be_empty
      end

      it "rejects has with unknown value" do
        result = described_class.call("has:banana")
        expect(result.tokens).to be_empty
        expect(result.errors.size).to eq(1)
      end

      it "accepts has:asset" do
        result = described_class.call("has:asset")
        expect(result.tokens.size).to eq(1)
      end

      it "rejects prop without =" do
        result = described_class.call("prop:statusdone")
        expect(result.tokens).to be_empty
        expect(result.errors.size).to eq(1)
      end

      it "accepts prop:status=done" do
        result = described_class.call("prop:status=done")
        expect(result.tokens.size).to eq(1)
        expect(result.tokens.first.value).to eq("status=done")
      end

      it "rejects created with invalid date" do
        result = described_class.call("created:abc")
        expect(result.tokens).to be_empty
        expect(result.errors.size).to eq(1)
      end

      it "accepts created:>2024-01" do
        result = described_class.call("created:>2024-01")
        expect(result.tokens.size).to eq(1)
      end

      it "accepts updated:<7d" do
        result = described_class.call("updated:<7d")
        expect(result.tokens.size).to eq(1)
      end
    end

    context "edge cases" do
      it "handles empty string" do
        result = described_class.call("")
        expect(result.tokens).to be_empty
        expect(result.text).to eq("")
        expect(result.errors).to be_empty
      end

      it "handles only whitespace" do
        result = described_class.call("   ")
        expect(result.tokens).to be_empty
        expect(result.text).to eq("")
      end

      it "handles nil" do
        result = described_class.call(nil)
        expect(result.tokens).to be_empty
        expect(result.text).to eq("")
      end

      it "handles unicode in values" do
        result = described_class.call("tag:neurociência")
        expect(result.tokens.size).to eq(1)
        expect(result.tokens.first.value).to eq("neurociência")
      end

      it "handles mixed valid and invalid operators" do
        result = described_class.call("tag:neuro orphan:maybe texto")
        expect(result.tokens.size).to eq(1)
        expect(result.tokens.first.operator).to eq(:tag)
        expect(result.errors.size).to eq(1)
        expect(result.text).to eq("orphan:maybe texto")
      end

      it "handles all operators at once" do
        query = "tag:x alias:y kind:z status:w link:a linkedfrom:b"
        result = described_class.call(query)
        expect(result.tokens.size).to eq(6)
      end
    end
  end
end
