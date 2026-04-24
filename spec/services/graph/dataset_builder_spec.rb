require "rails_helper"

RSpec.describe Graph::DatasetBuilder do
  def tagged(note, *names)
    names.each do |name|
      tag = Tag.find_or_create_by!(name: name) { |t| t.color_hex = "#888888"; t.tag_scope = "both" }
      NoteTag.create!(note: note, tag: tag)
    end
    note.reload
  end

  # Stand-in for TentacleRuntime::Session — we only need #alive? for state
  # derivation. Using a struct avoids coupling specs to the real Session's
  # PTY/dtach machinery.
  FakeLiveSession = Struct.new(:alive) { def alive?; alive end }

  def mark_alive(note_id)
    TentacleRuntime::SESSIONS[note_id] = FakeLiveSession.new(true)
  end

  def mark_runtime_dead(note_id)
    TentacleRuntime::SESSIONS[note_id] = FakeLiveSession.new(false)
  end

  before { TentacleRuntime::SESSIONS.clear }
  after  { TentacleRuntime::SESSIONS.clear }

  describe "avatar state from live runtime (TentacleRuntime::SESSIONS)" do
    let(:agent) do
      n = create(:note, :with_head_revision, title: "Especialista NeuraMD")
      tagged(n, "agente-team", "agente-especialista-neuramd")
    end
    let(:sleeping_agent) do
      n = create(:note, :with_head_revision, title: "Sleeping Agent")
      tagged(n, "agente-team", "agente-rubi")
    end

    it "marks agents with a live runtime session as awake and the rest as sleeping" do
      mark_alive(agent.id)
      sleeping_agent # realize without runtime entry

      result = described_class.call(scope: Note.all)

      notes_by_slug = result[:notes].index_by { |n| n[:slug] }
      expect(notes_by_slug[agent.slug][:avatar][:state]).to eq("awake")
      expect(notes_by_slug[sleeping_agent.slug][:avatar][:state]).to eq("sleeping")
    end

    # Regression guard for the adversarial round-2 finding: Supervisor only
    # sweeps stale `TentacleSession.alive` rows on a 5-min cadence, so a row
    # can linger with status=alive after the runtime died. Deriving avatar
    # state from the DB would falsely show operators "awake" exactly when
    # the runtime is gone.
    it "treats agents with a stale TentacleSession.alive DB row but no live runtime session as sleeping" do
      create(:tentacle_session, note: agent) # DB says alive
      # No SESSIONS[agent.id] — runtime is dead

      result = described_class.call(scope: Note.all)

      payload = result[:notes].find { |n| n[:slug] == agent.slug }
      expect(payload[:avatar][:state]).to eq("sleeping")
    end

    it "treats agents whose runtime session is present but not alive as sleeping" do
      mark_runtime_dead(agent.id)

      result = described_class.call(scope: Note.all)

      payload = result[:notes].find { |n| n[:slug] == agent.slug }
      expect(payload[:avatar][:state]).to eq("sleeping")
    end

    it "does not emit avatar for non-agent notes" do
      plain = create(:note, :with_head_revision, title: "Plain")

      result = described_class.call(scope: Note.where(id: plain.id))

      expect(result[:notes].first).not_to have_key(:avatar)
    end

    it "does not re-query tentacle_sessions for avatar state (live runtime is the source)" do
      5.times do |i|
        n = create(:note, :with_head_revision, title: "Agent #{i}")
        tagged(n, "agente-team", "agente-rubi")
        mark_alive(n.id) if i.even?
      end

      queries = []
      callback = ->(_, _, _, _, payload) do
        sql = payload[:sql]
        queries << sql if sql =~ /FROM\s+"?tentacle_sessions"?/i && sql !~ /SCHEMA|pg_/i
      end

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        described_class.call(scope: Note.all)
      end

      expect(queries).to be_empty,
        "expected zero tentacle_sessions queries (runtime is the source), got #{queries.inspect}"
    end
  end
end
