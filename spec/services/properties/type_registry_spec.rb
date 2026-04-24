require "rails_helper"

RSpec.describe Properties::TypeRegistry do
  describe ".handler_for" do
    it "returns the handler module for a known type" do
      expect(described_class.handler_for("text")).to eq(Properties::Types::Text)
    end

    it "raises for an unknown type" do
      expect { described_class.handler_for("color") }.to raise_error(ExtensionPoint::UnknownExtension, /color/)
    end
  end

  describe ".cast" do
    it "delegates to the type handler" do
      expect(described_class.cast("number", "42")).to eq(42)
    end
  end

  describe ".validate" do
    it "delegates to the type handler" do
      errors = described_class.validate("text", "hello")
      expect(errors).to be_empty
    end

    it "returns errors for invalid values" do
      errors = described_class.validate("number", "not_a_number")
      expect(errors).to include("must be a number")
    end
  end

  describe ".normalize" do
    it "delegates to the type handler" do
      expect(described_class.normalize("enum", " Draft ")).to eq("draft")
    end
  end

  describe "all V1 types are registered" do
    PropertyDefinition::VALUE_TYPES.each do |type_name|
      it "has a handler for '#{type_name}' with cast, normalize, validate" do
        handler = described_class.handler_for(type_name)
        expect(handler).to respond_to(:cast)
        expect(handler).to respond_to(:normalize)
        expect(handler).to respond_to(:validate)
      end
    end
  end
end

RSpec.describe "Properties::Types" do
  describe Properties::Types::Text do
    it "casts to stripped string" do
      expect(described_class.cast("  hello  ")).to eq("hello")
    end

    it "validates max length" do
      errors = described_class.validate("a" * 501)
      expect(errors).to include(/too long/)
    end

    it "passes for valid text" do
      expect(described_class.validate("hello")).to be_empty
    end

    describe "config.pattern" do
      let(:hex_pattern) { "\\A#(?:[0-9A-Fa-f]{3}|[0-9A-Fa-f]{6})\\z" }

      it "accepts values matching the pattern" do
        expect(described_class.validate("#abc", {"pattern" => hex_pattern})).to be_empty
        expect(described_class.validate("#AABBCC", {"pattern" => hex_pattern})).to be_empty
      end

      it "rejects values not matching the pattern with a clear error" do
        errors = described_class.validate("banana", {"pattern" => hex_pattern})
        expect(errors).to include(/format/i)
      end

      it "rejects 'rgba(...)' when hex pattern is configured" do
        errors = described_class.validate("rgba(0,0,0,1)", {"pattern" => hex_pattern})
        expect(errors).not_to be_empty
      end

      it "ignores a malformed pattern string instead of crashing writes" do
        errors = described_class.validate("anything", {"pattern" => "[unclosed"})
        expect(errors).to be_empty
      end

      it "is a no-op when config has no pattern (backwards compat with existing text PDs)" do
        expect(described_class.validate("anything", {})).to be_empty
        expect(described_class.validate("anything", {"pattern" => nil})).to be_empty
      end

      it "runs after max-length check — does not flag format when text is oversized" do
        errors = described_class.validate("a" * 501, {"pattern" => hex_pattern})
        expect(errors).to include(/too long/)
        expect(errors).not_to include(/format/i)
      end
    end
  end

  describe Properties::Types::LongText do
    it "allows up to 10_000 characters" do
      expect(described_class.validate("a" * 10_000)).to be_empty
    end

    it "rejects over 10_000 characters" do
      errors = described_class.validate("a" * 10_001)
      expect(errors).to include(/too long/)
    end
  end

  describe Properties::Types::Number do
    it "casts string integer" do
      expect(described_class.cast("42")).to eq(42)
    end

    it "casts string float" do
      expect(described_class.cast("3.14")).to eq(3.14)
    end

    it "passes through numeric values" do
      expect(described_class.cast(7)).to eq(7)
    end

    it "validates non-numeric" do
      errors = described_class.validate("abc")
      expect(errors).to include("must be a number")
    end

    it "validates min constraint" do
      errors = described_class.validate(-1, "min" => 0)
      expect(errors).to include("must be >= 0")
    end

    it "validates max constraint" do
      errors = described_class.validate(101, "max" => 100)
      expect(errors).to include("must be <= 100")
    end

    it "passes for valid number in range" do
      expect(described_class.validate(50, "min" => 0, "max" => 100)).to be_empty
    end
  end

  describe Properties::Types::Boolean do
    it "casts 'true' string" do
      expect(described_class.cast("true")).to be true
    end

    it "casts 'false' string" do
      expect(described_class.cast("false")).to be false
    end

    it "casts '1' to true" do
      expect(described_class.cast("1")).to be true
    end

    it "passes through boolean values" do
      expect(described_class.cast(true)).to be true
    end

    it "rejects non-boolean after cast failure" do
      errors = described_class.validate("maybe")
      expect(errors).to include("must be a boolean")
    end
  end

  describe Properties::Types::Date do
    it "casts a valid date string" do
      expect(described_class.cast("2026-03-31")).to eq("2026-03-31")
    end

    it "casts non-ISO format" do
      expect(described_class.cast("March 31, 2026")).to eq("2026-03-31")
    end

    it "rejects unparseable date" do
      errors = described_class.validate("not-a-date")
      expect(errors).to include(/ISO 8601 date/)
    end

    it "passes for valid ISO date" do
      expect(described_class.validate("2026-03-31")).to be_empty
    end
  end

  describe Properties::Types::Datetime do
    it "casts a valid ISO datetime" do
      expect(described_class.cast("2026-03-31T14:30:00Z")).to eq("2026-03-31T14:30:00Z")
    end

    it "rejects non-datetime" do
      errors = described_class.validate("not-a-datetime")
      expect(errors).to include(/ISO 8601 datetime/)
    end

    it "passes for valid ISO datetime" do
      expect(described_class.validate("2026-03-31T14:30:00Z")).to be_empty
    end
  end

  describe Properties::Types::Enum do
    let(:config) { {"options" => %w[draft review published]} }

    it "casts to stripped string" do
      expect(described_class.cast(" draft ")).to eq("draft")
    end

    it "normalizes to downcase" do
      expect(described_class.normalize("Draft")).to eq("draft")
    end

    it "validates value is in options" do
      expect(described_class.validate("draft", config)).to be_empty
    end

    it "rejects value not in options" do
      errors = described_class.validate("archived", config)
      expect(errors).to include(/must be one of/)
    end
  end

  describe Properties::Types::MultiEnum do
    let(:config) { {"options" => %w[tag_a tag_b tag_c]} }

    it "casts comma-separated string to array" do
      expect(described_class.cast("tag_a, tag_b")).to eq(%w[tag_a tag_b])
    end

    it "passes through arrays" do
      expect(described_class.cast(%w[tag_a])).to eq(%w[tag_a])
    end

    it "normalizes: downcase, uniq, sort" do
      expect(described_class.normalize(%w[Tag_B tag_a Tag_B])).to eq(%w[tag_a tag_b])
    end

    it "validates all values in options" do
      expect(described_class.validate(%w[tag_a tag_b], config)).to be_empty
    end

    it "rejects invalid values" do
      errors = described_class.validate(%w[tag_a tag_x], config)
      expect(errors.first).to include("tag_x")
    end
  end

  describe Properties::Types::Url do
    it "passes for valid HTTP URL" do
      expect(described_class.validate("https://example.com")).to be_empty
    end

    it "rejects non-HTTP URL" do
      errors = described_class.validate("ftp://example.com")
      expect(errors).to include(/valid URL with scheme/)
    end

    it "rejects malformed URL" do
      errors = described_class.validate("not a url at all\\")
      expect(errors.first).to match(/valid URL/)
    end
  end

  describe Properties::Types::NoteReference do
    it "passes for an existing active note UUID" do
      note = create(:note, title: "Referenced")
      expect(described_class.validate(note.id)).to be_empty
    end

    it "rejects non-UUID" do
      errors = described_class.validate("not-a-uuid")
      expect(errors).to include("must be a valid UUID")
    end

    it "rejects deleted note UUID" do
      note = create(:note, :deleted, title: "Gone")
      errors = described_class.validate(note.id)
      expect(errors).to include("references a non-existent note")
    end
  end

  describe Properties::Types::List do
    it "casts comma-separated string" do
      expect(described_class.cast("a, b, c")).to eq(%w[a b c])
    end

    it "passes through arrays" do
      expect(described_class.cast(%w[x y])).to eq(%w[x y])
    end

    it "normalizes: strips items, rejects blanks" do
      expect(described_class.normalize(["a ", " ", "b"])).to eq(%w[a b])
    end

    it "validates array of strings" do
      expect(described_class.validate(%w[a b])).to be_empty
    end

    it "rejects non-string array items" do
      errors = described_class.validate([1, 2])
      expect(errors).to include("must be an array of strings")
    end
  end
end
