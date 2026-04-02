require "rails_helper"

RSpec.describe Aliases::SetService do
  let(:note) { create(:note, :with_head_revision, title: "Cardiologia") }

  describe ".call" do
    it "sets aliases on a note with no prior aliases" do
      result = described_class.call(note: note, aliases: ["Cardio", "Heart"])

      expect(result.aliases).to contain_exactly("Cardio", "Heart")
      expect(note.note_aliases.pluck(:name)).to contain_exactly("Cardio", "Heart")
    end

    it "replaces existing aliases" do
      described_class.call(note: note, aliases: ["Old Alias"])
      result = described_class.call(note: note, aliases: ["New Alias"])

      expect(result.aliases).to eq(["New Alias"])
      expect(note.note_aliases.count).to eq(1)
    end

    it "clears all aliases when given empty array" do
      described_class.call(note: note, aliases: ["Cardio"])
      result = described_class.call(note: note, aliases: [])

      expect(result.aliases).to be_empty
      expect(note.note_aliases.count).to eq(0)
    end

    it "deduplicates input (case-insensitive)" do
      result = described_class.call(note: note, aliases: ["Cardio", "cardio", "CARDIO"])

      expect(result.aliases.size).to eq(1)
    end

    it "strips whitespace and rejects blanks" do
      result = described_class.call(note: note, aliases: ["  Cardio  ", "", "  "])

      expect(result.aliases).to eq(["Cardio"])
    end

    it "preserves aliases that remain in the new set" do
      described_class.call(note: note, aliases: ["Cardio", "Heart"])
      original_ids = note.note_aliases.order(:name).pluck(:id)

      described_class.call(note: note, aliases: ["Cardio", "Coração"])

      remaining_cardio = note.note_aliases.find_by("lower(name) = ?", "cardio")
      expect(remaining_cardio.id).to eq(original_ids.first)
    end

    it "raises when alias collides with another note" do
      other_note = create(:note, :with_head_revision)
      create(:note_alias, note: other_note, name: "Taken")

      expect {
        described_class.call(note: note, aliases: ["Taken"])
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "publishes note.aliases_changed event" do
      events = []
      ActiveSupport::Notifications.subscribe("neuramd.note.aliases_changed") do |*, payload|
        events << payload
      end

      described_class.call(note: note, aliases: ["Cardio"])

      expect(events.size).to eq(1)
      expect(events.first[:note_id]).to eq(note.id)
      expect(events.first[:aliases]).to eq(["Cardio"])
    ensure
      ActiveSupport::Notifications.unsubscribe("neuramd.note.aliases_changed")
    end
  end
end
