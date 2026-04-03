require "rails_helper"

RSpec.describe "Extension isolation" do
  describe "search operator failure" do
    it "failing operator does not crash search" do
      broken = Module.new do
        def self.apply(_scope, _value)
          raise "boom"
        end
      end
      Search::Dsl::OperatorRegistry.register(:broken, broken)

      create(:note, title: "Safe Note")
      result = Search::NoteQueryService.call(
        scope: Note.active,
        query: "broken:x"
      )

      # Search completes without error — the broken operator is silently skipped
      expect(result.error).to be_nil
      expect(result.notes).not_to be_nil
    ensure
      Search::Dsl::OperatorRegistry.send(:registry).delete("broken")
    end

    it "returns results despite failing operator" do
      broken = Module.new do
        def self.apply(_scope, _value)
          raise "boom"
        end
      end
      Search::Dsl::OperatorRegistry.register(:broken, broken)

      # Create note with revision so with_latest_content includes it
      note = create(:note, title: "Resilient")
      create(:note_revision, note: note, content_markdown: "test content")
      note.update!(head_revision: note.note_revisions.last)

      result = Search::NoteQueryService.call(
        scope: Note.active,
        query: "broken:x"
      )

      expect(result.notes.map(&:title)).to include("Resilient")
    ensure
      Search::Dsl::OperatorRegistry.send(:registry).delete("broken")
    end
  end

  describe "domain event subscriber failure" do
    it "failing subscriber does not crash note operations" do
      sub = DomainEventSubscriber.safe_subscribe("neuramd.note.created") do |*, _payload|
        raise "subscriber boom"
      end

      expect {
        create(:note, title: "Survivor Note")
      }.not_to raise_error
    ensure
      ActiveSupport::Notifications.unsubscribe(sub)
    end
  end

  describe "instrumentation" do
    it "invoke_safe emits extension.invoke event" do
      registry = Class.new do
        include ExtensionPoint
        contract :apply
      end
      handler = Module.new { def self.apply(scope, value) = "ok" }
      registry.register(:test_op, handler)

      events = []
      sub = ActiveSupport::Notifications.subscribe("extension.invoke") do |*, payload|
        events << payload
      end

      registry.invoke_safe(:test_op, nil, "val")

      expect(events.size).to eq(1)
      expect(events.first[:handler_name]).to eq("test_op")
    ensure
      ActiveSupport::Notifications.unsubscribe(sub)
    end

    it "invoke_safe emits extension.error on failure" do
      registry = Class.new do
        include ExtensionPoint
        contract :apply
      end
      broken = Module.new { def self.apply(scope, value) = raise("kaboom") }
      registry.register(:fail_op, broken)

      errors = []
      sub = ActiveSupport::Notifications.subscribe("extension.error") do |*, payload|
        errors << payload
      end

      registry.invoke_safe(:fail_op, nil, "val")

      expect(errors.size).to eq(1)
      expect(errors.first[:error_class]).to eq("RuntimeError")
      expect(errors.first[:error_message]).to eq("kaboom")
    ensure
      ActiveSupport::Notifications.unsubscribe(sub)
    end
  end
end
