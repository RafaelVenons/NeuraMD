require "rails_helper"

RSpec.describe Properties::SetService do
  let(:user) { create(:user) }
  let(:note) { create(:note, :with_head_revision, title: "Props Test") }

  before do
    create(:property_definition, key: "status", value_type: "enum", config: {"options" => %w[draft review published]})
    create(:property_definition, key: "priority", value_type: "number")
    create(:property_definition, key: "due_date", value_type: "date")
    create(:property_definition, key: "tags_list", value_type: "list")
  end

  describe ".call" do
    it "sets a single property and creates a checkpoint" do
      revision = described_class.call(note: note, changes: {"status" => "draft"}, author: user)

      expect(revision).to be_a(NoteRevision)
      expect(revision.properties_data).to eq({"status" => "draft"})
    end

    it "sets multiple properties at once" do
      revision = described_class.call(
        note: note,
        changes: {"status" => "review", "priority" => 5},
        author: user
      )

      expect(revision.properties_data).to eq({"status" => "review", "priority" => 5})
    end

    it "preserves existing properties when setting new ones" do
      described_class.call(note: note, changes: {"status" => "draft"}, author: user)
      note.reload
      revision = described_class.call(note: note, changes: {"priority" => 3}, author: user)

      expect(revision.properties_data).to eq({"status" => "draft", "priority" => 3})
    end

    it "removes a property when value is nil" do
      described_class.call(note: note, changes: {"status" => "draft", "priority" => 1}, author: user)
      note.reload
      revision = described_class.call(note: note, changes: {"status" => nil}, author: user)

      expect(revision.properties_data).to eq({"priority" => 1})
    end

    it "casts values through the type handler" do
      revision = described_class.call(note: note, changes: {"priority" => "42"}, author: user)
      expect(revision.properties_data["priority"]).to eq(42)
    end

    it "preserves content from the previous revision" do
      original_content = note.head_revision.content_markdown
      revision = described_class.call(note: note, changes: {"status" => "draft"}, author: user)

      expect(revision.content_markdown).to eq(original_content)
    end

    it "raises UnknownKeyError for undefined keys" do
      expect {
        described_class.call(note: note, changes: {"unknown_key" => "value"}, author: user)
      }.to raise_error(Properties::SetService::UnknownKeyError, /unknown_key/)
    end

    it "raises ValidationError for invalid values" do
      expect {
        described_class.call(note: note, changes: {"status" => "invalid_option"}, author: user)
      }.to raise_error(Properties::SetService::ValidationError) { |e|
        expect(e.details).to have_key("status")
      }
    end

    it "does not create a revision when validation fails" do
      expect {
        described_class.call(note: note, changes: {"status" => "bad"}, author: user) rescue nil
      }.not_to change { note.note_revisions.count }
    end

    it "emits property.changed domain events" do
      events = []
      callback = ->(_name, _s, _f, _id, payload) { events << payload }

      ActiveSupport::Notifications.subscribed(callback, "neuramd.property.changed") do
        described_class.call(note: note, changes: {"status" => "draft", "priority" => 1}, author: user)
      end

      expect(events.size).to eq(2)
      expect(events.map { |e| e[:property] }).to contain_exactly("status", "priority")
      expect(events.find { |e| e[:property] == "status" }[:action]).to eq("set")
    end

    it "emits 'updated' action when property already exists" do
      described_class.call(note: note, changes: {"status" => "draft"}, author: user)
      note.reload

      events = []
      callback = ->(_name, _s, _f, _id, payload) { events << payload }

      ActiveSupport::Notifications.subscribed(callback, "neuramd.property.changed") do
        described_class.call(note: note, changes: {"status" => "published"}, author: user)
      end

      expect(events.first[:action]).to eq("updated")
    end

    it "emits 'removed' action when property is deleted" do
      described_class.call(note: note, changes: {"status" => "draft"}, author: user)
      note.reload

      events = []
      callback = ->(_name, _s, _f, _id, payload) { events << payload }

      ActiveSupport::Notifications.subscribed(callback, "neuramd.property.changed") do
        described_class.call(note: note, changes: {"status" => nil}, author: user)
      end

      expect(events.first[:action]).to eq("removed")
    end

    it "normalizes values before storing" do
      revision = described_class.call(note: note, changes: {"status" => " Draft "}, author: user)
      expect(revision.properties_data["status"]).to eq("draft")
    end
  end

  describe "lenient mode (strict: false)" do
    it "stores invalid values without raising" do
      revision = described_class.call(
        note: note,
        changes: {"status" => "bad_value"},
        author: user,
        strict: false
      )

      expect(revision.properties_data["status"]).to eq("bad_value")
    end

    it "tracks validation errors in _errors key" do
      revision = described_class.call(
        note: note,
        changes: {"status" => "bad_value"},
        author: user,
        strict: false
      )

      expect(revision.properties_data["_errors"]).to have_key("status")
      expect(revision.properties_data["_errors"]["status"].first).to include("must be one of")
    end

    it "clears _errors for a key when it becomes valid" do
      described_class.call(note: note, changes: {"status" => "bad"}, author: user, strict: false)
      note.reload

      revision = described_class.call(note: note, changes: {"status" => "draft"}, author: user, strict: false)
      expect(revision.properties_data["_errors"]).to be_nil
    end

    it "does not include _errors key when all properties are valid" do
      revision = described_class.call(
        note: note,
        changes: {"status" => "draft"},
        author: user,
        strict: false
      )

      expect(revision.properties_data).not_to have_key("_errors")
    end

    it "removes _errors for a key when the property is removed" do
      described_class.call(note: note, changes: {"status" => "bad"}, author: user, strict: false)
      note.reload

      revision = described_class.call(note: note, changes: {"status" => nil}, author: user, strict: false)
      expect(revision.properties_data).not_to have_key("_errors")
    end

    it "preserves _errors for other keys when fixing one" do
      described_class.call(
        note: note,
        changes: {"status" => "bad", "priority" => "not_num"},
        author: user,
        strict: false
      )
      note.reload

      revision = described_class.call(note: note, changes: {"status" => "draft"}, author: user, strict: false)
      expect(revision.properties_data["_errors"]).to have_key("priority")
      expect(revision.properties_data["_errors"]).not_to have_key("status")
    end
  end
end
