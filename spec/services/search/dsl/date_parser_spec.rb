require "rails_helper"

RSpec.describe Search::Dsl::DateParser do
  describe ".call" do
    context "relative dates" do
      it "parses >7d as gt with timestamp 7 days ago" do
        result = described_class.call(">7d")
        expect(result).to be_a(described_class::Result)
        expect(result.comparator).to eq(:gt)
        expect(result.timestamp).to be_within(2.seconds).of(7.days.ago)
      end

      it "parses <30d as lt with timestamp 30 days ago" do
        result = described_class.call("<30d")
        expect(result.comparator).to eq(:lt)
        expect(result.timestamp).to be_within(2.seconds).of(30.days.ago)
      end

      it "parses >2w as gt with timestamp 2 weeks ago" do
        result = described_class.call(">2w")
        expect(result.comparator).to eq(:gt)
        expect(result.timestamp).to be_within(2.seconds).of(2.weeks.ago)
      end

      it "parses <3m as lt with timestamp 3 months ago" do
        result = described_class.call("<3m")
        expect(result.comparator).to eq(:lt)
        expect(result.timestamp).to be_within(2.seconds).of(3.months.ago)
      end

      it "parses >1y as gt with timestamp 1 year ago" do
        result = described_class.call(">1y")
        expect(result.comparator).to eq(:gt)
        expect(result.timestamp).to be_within(2.seconds).of(1.year.ago)
      end
    end

    context "absolute dates" do
      it "parses >2024-01 as gt with first day of January 2024" do
        result = described_class.call(">2024-01")
        expect(result.comparator).to eq(:gt)
        expect(result.timestamp).to eq(Time.zone.parse("2024-01-01"))
      end

      it "parses <2024-01-15 as lt with that exact date" do
        result = described_class.call("<2024-01-15")
        expect(result.comparator).to eq(:lt)
        expect(result.timestamp).to eq(Time.zone.parse("2024-01-15"))
      end

      it "parses >2024 as gt with first day of 2024" do
        result = described_class.call(">2024")
        expect(result.comparator).to eq(:gt)
        expect(result.timestamp).to eq(Time.zone.parse("2024-01-01"))
      end
    end

    context "invalid values" do
      it "returns nil for garbage" do
        expect(described_class.call(">abc")).to be_nil
      end

      it "returns nil for missing comparator" do
        expect(described_class.call("2024-01")).to be_nil
      end

      it "returns nil for empty string" do
        expect(described_class.call("")).to be_nil
      end

      it "returns nil for invalid date like >2024-13" do
        expect(described_class.call(">2024-13")).to be_nil
      end
    end
  end
end
