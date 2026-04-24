require "rails_helper"

RSpec.describe Graph::DatasetBuilder do
  def tagged(note, *names)
    names.each do |name|
      tag = Tag.find_or_create_by!(name: name) { |t| t.color_hex = "#888888"; t.tag_scope = "both" }
      NoteTag.create!(note: note, tag: tag)
    end
    note.reload
  end

  describe "avatar state from live TentacleSessions" do
    let(:agent) do
      n = create(:note, :with_head_revision, title: "Especialista NeuraMD")
      tagged(n, "agente-team", "agente-especialista-neuramd")
    end
    let(:sleeping_agent) do
      n = create(:note, :with_head_revision, title: "Sleeping Agent")
      tagged(n, "agente-team", "agente-rubi")
    end

    it "marks agents with alive sessions as awake and the rest as sleeping" do
      agent
      sleeping_agent
      create(:tentacle_session, note: agent)
      create(:tentacle_session, :exited, note: sleeping_agent)

      result = described_class.call(scope: Note.all)

      notes_by_slug = result[:notes].index_by { |n| n[:slug] }
      expect(notes_by_slug[agent.slug][:avatar][:state]).to eq("awake")
      expect(notes_by_slug[sleeping_agent.slug][:avatar][:state]).to eq("sleeping")
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
        create(:tentacle_session, note: n) if i.even?
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
