require "rails_helper"

RSpec.describe Graph::DatasetBuilder do
  def tagged(note, *names)
    names.each do |name|
      tag = Tag.find_or_create_by!(name: name) { |t| t.color_hex = "#888888"; t.tag_scope = "both" }
      NoteTag.create!(note: note, tag: tag)
    end
    note.reload
  end

  # Freshness gate: a session whose last_seen_at is within this window counts
  # as alive. Must stay in sync with DatasetBuilder::LIVE_SESSION_FRESHNESS.
  # Specs exercise rows on both sides of the window.
  def fresh_session_for(note)
    create(:tentacle_session, note: note, last_seen_at: Time.current)
  end

  def stale_session_for(note)
    create(:tentacle_session,
      note: note,
      last_seen_at: (Graph::DatasetBuilder::LIVE_SESSION_FRESHNESS + 1.minute).ago)
  end

  describe "avatar state from DB + freshness gate (cross-worker safe)" do
    let(:agent) do
      n = create(:note, :with_head_revision, title: "Especialista NeuraMD")
      tagged(n, "agente-team", "agente-especialista-neuramd")
    end
    let(:sleeping_agent) do
      n = create(:note, :with_head_revision, title: "Sleeping Agent")
      tagged(n, "agente-team", "agente-rubi")
    end

    it "marks agents with a fresh TentacleSession.alive row as awake" do
      fresh_session_for(agent)
      sleeping_agent # no session row

      result = described_class.call(scope: Note.all)

      notes_by_slug = result[:notes].index_by { |n| n[:slug] }
      expect(notes_by_slug[agent.slug][:avatar][:state]).to eq("awake")
      expect(notes_by_slug[sleeping_agent.slug][:avatar][:state]).to eq("sleeping")
    end

    # Regression for round-2 finding (stale alive rows): a session whose
    # last_seen_at is older than the freshness window is treated as sleeping
    # even when status=alive lingers in the DB. SupervisorJob will reap it on
    # the next tick, but the graph must not show awake in the meantime.
    it "treats agents whose TentacleSession.alive row is stale as sleeping" do
      stale_session_for(agent)

      result = described_class.call(scope: Note.all)

      payload = result[:notes].find { |n| n[:slug] == agent.slug }
      expect(payload[:avatar][:state]).to eq("sleeping")
    end

    # Regression for round-4 #2 (process-local SESSIONS): DatasetBuilder must
    # not consult TentacleRuntime::SESSIONS. Cross-worker correctness depends
    # on a shared (DB) source.
    it "ignores in-process TentacleRuntime::SESSIONS (multi-worker safety)" do
      TentacleRuntime::SESSIONS[agent.id] = Struct.new(:alive).new(true).tap { |s| s.define_singleton_method(:alive?) { true } }
      # No DB row → must be sleeping even though the in-memory map says alive
      result = described_class.call(scope: Note.all)
      payload = result[:notes].find { |n| n[:slug] == agent.slug }
      expect(payload[:avatar][:state]).to eq("sleeping")
    ensure
      TentacleRuntime::SESSIONS.clear
    end

    it "treats an exited session as sleeping regardless of last_seen_at" do
      create(:tentacle_session, :exited, note: agent, last_seen_at: Time.current)

      result = described_class.call(scope: Note.all)

      payload = result[:notes].find { |n| n[:slug] == agent.slug }
      expect(payload[:avatar][:state]).to eq("sleeping")
    end

    it "does not emit avatar for non-agent notes" do
      plain = create(:note, :with_head_revision, title: "Plain")

      result = described_class.call(scope: Note.where(id: plain.id))

      expect(result[:notes].first).not_to have_key(:avatar)
    end

    it "runs the alive-session query once regardless of agent count (N+1 guard)" do
      5.times do |i|
        n = create(:note, :with_head_revision, title: "Agent #{i}")
        tagged(n, "agente-team", "agente-rubi")
        fresh_session_for(n) if i.even?
      end

      queries = []
      callback = ->(_, _, _, _, payload) do
        sql = payload[:sql]
        queries << sql if sql =~ /FROM\s+"?tentacle_sessions"?/i && sql !~ /SCHEMA|pg_/i
      end

      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        described_class.call(scope: Note.all)
      end

      expect(queries.size).to eq(1), "expected 1 tentacle_sessions query, got #{queries.size}: #{queries.inspect}"
    end
  end
end
