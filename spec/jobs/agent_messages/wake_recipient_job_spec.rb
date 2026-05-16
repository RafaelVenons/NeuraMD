require "rails_helper"

RSpec.describe AgentMessages::WakeRecipientJob, type: :job do
  let(:token) { "stub-s2s-token-#{SecureRandom.hex(8)}" }
  let(:sender) { create(:note, title: "Sender") }

  before do
    allow(Rails.application.credentials).to receive(:agent_s2s_token).and_return(token)
  end

  def agent_note(title: "Agent #{SecureRandom.hex(4)}")
    note = create(:note, title: title)
    note.tags << Tag.find_or_create_by!(name: "agente-test")
    note.reload
  end

  def stub_post(status: 201, body: '{"activated":true,"reused":false,"wake_coalesced":false,"routed_prompt_delivered":true}')
    calls = []
    allow_any_instance_of(described_class).to receive(:post_json) do |_job, uri, payload, auth_token|
      calls << {uri: uri, payload: payload, token: auth_token}
      [body, status]
    end
    calls
  end

  def wake_state(note)
    AgentWakeState.find_by(note_id: note.id)
  end

  describe "#perform" do
    it "does nothing when the recipient note carries no agent tag" do
      plain = create(:note, title: "Plain note")
      AgentMessage.create!(from_note: sender, to_note: plain, content: "hi")
      calls = stub_post

      described_class.perform_now(plain.id)

      expect(calls).to be_empty
    end

    it "does nothing when tentacle operations are disabled at run time" do
      # A job (or follow-up) may already be queued when an operator
      # disables the feature for a rollback — perform must re-check the
      # gate, not just trust the enqueue-time callback check.
      note = agent_note
      AgentMessage.create!(from_note: sender, to_note: note, content: "hi")
      calls = stub_post
      allow(Tentacles::Authorization).to receive(:enabled?).and_return(false)

      described_class.perform_now(note.id)

      expect(calls).to be_empty
      expect(wake_state(note)).to be_nil
    end

    it "does nothing when the note no longer exists" do
      calls = stub_post
      expect { described_class.perform_now(SecureRandom.uuid) }.not_to raise_error
      expect(calls).to be_empty
    end

    it "does nothing when the note is soft-deleted" do
      note = agent_note
      AgentMessage.create!(from_note: sender, to_note: note, content: "hi")
      note.update!(deleted_at: Time.current)
      calls = stub_post

      described_class.perform_now(note.id)

      expect(calls).to be_empty
    end

    it "claims a wake slot and POSTs the S2S activate endpoint for a pending inbox" do
      note = agent_note
      AgentMessage.create!(from_note: sender, to_note: note, content: "task for you")
      calls = stub_post

      described_class.perform_now(note.id)

      expect(calls.size).to eq(1)
      expect(calls.first[:token]).to eq(token)
      expect(calls.first[:uri].path).to eq("/api/s2s/tentacles/#{note.slug}/activate")
      expect(calls.first[:payload][:initial_prompt]).to include("1 mensagem")
      expect(calls.first[:payload][:initial_prompt]).to include(note.slug)
      # coalesce_wake lets SessionControl skip a redundant nudge to a
      # live session it just woke (liveness-aware dedup the worker can't do).
      expect(calls.first[:payload][:coalesce_wake]).to be(true)
      expect(wake_state(note).last_wake_attempt_at).to be_present
    end

    it "schedules a follow-up re-check past the debounce window after a successful wake" do
      note = agent_note
      AgentMessage.create!(from_note: sender, to_note: note, content: "hi")
      stub_post

      # The follow-up re-check covers messages that arrive while the slot
      # is held and would otherwise be stranded if the woken agent drains
      # its inbox and exits (Codex finding: fixed-timer debounce strands
      # messages).
      expect { described_class.perform_now(note.id) }
        .to have_enqueued_job(described_class)
        .with(note.id)
        .at(a_value_within(5.seconds).of((described_class::DEBOUNCE_WINDOW + described_class::FOLLOWUP_BUFFER).from_now))
    end

    it "debounces a burst — a recent wake attempt suppresses another wake" do
      note = agent_note
      AgentMessage.create!(from_note: sender, to_note: note, content: "one")
      AgentMessage.create!(from_note: sender, to_note: note, content: "two")
      AgentWakeState.create!(note_id: note.id, last_wake_attempt_at: 2.seconds.ago)
      calls = stub_post

      described_class.perform_now(note.id)

      expect(calls).to be_empty
    end

    it "wakes again once the debounce window has elapsed" do
      note = agent_note
      msg = AgentMessage.create!(from_note: sender, to_note: note, content: "one")
      msg.update_column(:created_at, 30.seconds.ago)
      AgentWakeState.create!(note_id: note.id, last_wake_attempt_at: 2.minutes.ago)
      calls = stub_post

      described_class.perform_now(note.id)

      expect(calls.size).to eq(1)
    end

    it "does not re-wake a slow agent for messages the previous wake already covered" do
      note = agent_note
      # Wake happened 90s ago — debounce window long elapsed.
      AgentWakeState.create!(note_id: note.id, last_wake_attempt_at: 90.seconds.ago)
      # A message that existed before that wake: the wake already told
      # the agent about it; it is still pending only because the agent
      # is slow to drain. Re-waking would re-activate an in-flight
      # backlog (Codex finding: follow-up re-activates the same set).
      msg = AgentMessage.create!(from_note: sender, to_note: note, content: "old, slow to drain")
      msg.update_column(:created_at, 3.minutes.ago)
      calls = stub_post

      described_class.perform_now(note.id)

      expect(calls).to be_empty
    end

    it "re-wakes for a message created after the previous wake" do
      note = agent_note
      AgentWakeState.create!(note_id: note.id, last_wake_attempt_at: 90.seconds.ago)
      # Genuinely uncovered — arrived after the last wake.
      msg = AgentMessage.create!(from_note: sender, to_note: note, content: "new since last wake")
      msg.update_column(:created_at, 30.seconds.ago)
      calls = stub_post

      described_class.perform_now(note.id)

      expect(calls.size).to eq(1)
    end

    it "does not POST or consume the debounce slot when the inbox has no pending messages" do
      note = agent_note
      AgentMessage.create!(
        from_note: sender, to_note: note, content: "already read", delivered_at: 1.minute.ago
      )
      calls = stub_post

      described_class.perform_now(note.id)

      expect(calls).to be_empty
      # Slot must stay untouched so a message arriving moments later
      # still triggers a wake (Codex finding: lost-wake-before-pending-check).
      expect(wake_state(note)).to be_nil
    end

    it "releases the slot and reschedules a retry on a 5xx response" do
      note = agent_note
      AgentMessage.create!(from_note: sender, to_note: note, content: "hi")
      stub_post(status: 503, body: '{"error":"runtime down"}')

      expect { described_class.perform_now(note.id) }
        .to have_enqueued_job(described_class).with(note.id)
      # Slot released so the retry is not suppressed by its own debounce
      # (Codex finding: wake-failure-treated-as-debounced-success).
      expect(wake_state(note).last_wake_attempt_at).to be_nil
    end

    it "releases the slot and reschedules a retry when the activate call hits a network error" do
      note = agent_note
      AgentMessage.create!(from_note: sender, to_note: note, content: "hi")
      allow_any_instance_of(described_class).to receive(:post_json).and_raise(Errno::ECONNREFUSED)

      expect { described_class.perform_now(note.id) }
        .to have_enqueued_job(described_class).with(note.id)
      expect(wake_state(note).last_wake_attempt_at).to be_nil
    end

    it "releases the slot and reschedules a retry on a non-auth 4xx response" do
      note = agent_note
      AgentMessage.create!(from_note: sender, to_note: note, content: "hi")
      stub_post(status: 404, body: '{"error":"not found"}')

      # A 4xx wake was not delivered — the slot must not stay advanced
      # marking the triggering message covered (Codex finding: permanent
      # 4xx drops the pending set on the floor).
      expect { described_class.perform_now(note.id) }
        .to have_enqueued_job(described_class).with(note.id)
      expect(wake_state(note).last_wake_attempt_at).to be_nil
    end

    it "releases the slot and reschedules a retry on a 409 stale-config response" do
      note = agent_note
      AgentMessage.create!(from_note: sender, to_note: note, content: "hi")
      stub_post(status: 409, body: '{"error":"stale boot config","stale_boot_config":true}')

      # 409/422 are operator-fixable — retry_on gives a bounded window,
      # and the released slot keeps the original message eligible once
      # the worktree/config is fixed.
      expect { described_class.perform_now(note.id) }
        .to have_enqueued_job(described_class).with(note.id)
      expect(wake_state(note).last_wake_attempt_at).to be_nil
    end

    it "release_wake_slot does not erase a newer wake claim placed by a concurrent job" do
      note = agent_note
      old_claim = 30.seconds.ago
      newer_claim = 1.second.ago
      AgentWakeState.create!(note_id: note.id, last_wake_attempt_at: old_claim)
      # Simulate a newer job winning the slot while the older job's
      # activate was still in flight (CAS regression — Codex finding:
      # failed wake could erase a newer claim).
      AgentWakeState.where(note_id: note.id).update_all(last_wake_attempt_at: newer_claim)

      described_class.new.send(:release_wake_slot, note, claimed_at: old_claim)

      expect(wake_state(note).last_wake_attempt_at.to_i).to eq(newer_claim.to_i)
    end

    it "releases the slot and reschedules a follow-up when the spawn did not confirm prompt delivery" do
      note = agent_note
      AgentMessage.create!(from_note: sender, to_note: note, content: "hi")
      # Fresh spawn happened but SessionControl could not confirm the
      # initial_prompt landed (PTY readiness race) — the agent has not
      # actually been nudged for the triggering message (Codex finding:
      # routed_prompt_delivered=false must release the slot).
      stub_post(
        status: 201,
        body: '{"activated":true,"reused":false,"wake_coalesced":false,"routed_prompt_delivered":false}'
      )

      expect { described_class.perform_now(note.id) }
        .to have_enqueued_job(described_class).with(note.id)
      expect(wake_state(note).last_wake_attempt_at).to be_nil
    end

    it "releases the slot and reschedules a follow-up when the wake is coalesced" do
      note = agent_note
      AgentMessage.create!(from_note: sender, to_note: note, content: "hi")
      # 2xx but SessionControl skipped the write (session nudged moments
      # ago). "Recently nudged" is not "this message was delivered", so
      # the slot must be released and a follow-up scheduled past the
      # coalesce window (Codex finding: coalesced wakes suppress delivery).
      stub_post(status: 200, body: '{"activated":true,"reused":true,"wake_coalesced":true}')

      expect { described_class.perform_now(note.id) }
        .to have_enqueued_job(described_class).with(note.id)
      expect(wake_state(note).last_wake_attempt_at).to be_nil
    end

    it "fails loudly and releases the slot on a 401/403 auth rejection" do
      note = agent_note
      AgentMessage.create!(from_note: sender, to_note: note, content: "hi")
      stub_post(status: 403, body: '{"error":"forbidden"}')

      # An auth rejection means a broken/rotated token affecting every
      # agent — it must fail like the other misconfigurations, not be
      # swallowed as a per-note 4xx (Codex finding: 401/403 misclassified).
      expect { described_class.perform_now(note.id) }
        .to raise_error(described_class::WakeConfigurationError, /token/)
      expect(wake_state(note).last_wake_attempt_at).to be_nil
    end

    it "fails loudly and releases the slot when no S2S token is configured" do
      note = agent_note
      AgentMessage.create!(from_note: sender, to_note: note, content: "hi")
      allow_any_instance_of(described_class).to receive(:resolve_token).and_return(nil)

      # A missing token is a broken deploy — it must surface as a failed
      # job, not vanish into a silently consumed slot.
      expect { described_class.perform_now(note.id) }
        .to raise_error(described_class::WakeConfigurationError, /AGENT_S2S_TOKEN/)
      expect(wake_state(note).last_wake_attempt_at).to be_nil
    end

    it "fails loudly and releases the slot on unsafe non-loopback plaintext transport" do
      note = agent_note
      AgentMessage.create!(from_note: sender, to_note: note, content: "hi")
      allow_any_instance_of(described_class).to receive(:base_url).and_return("http://neuramd.example.com")

      expect { described_class.perform_now(note.id) }
        .to raise_error(described_class::WakeConfigurationError, /plaintext HTTP/)
      expect(wake_state(note).last_wake_attempt_at).to be_nil
    end

    it "fails loudly and releases the slot when NEURAMD_S2S_URL is unset outside dev/test" do
      note = agent_note
      AgentMessage.create!(from_note: sender, to_note: note, content: "hi")
      stub_post
      allow(Rails.env).to receive(:development?).and_return(false)
      allow(Rails.env).to receive(:test?).and_return(false)
      # Keep the run-time auth gate open: it also keys off dev/test env,
      # so the stubs above would otherwise short-circuit perform before
      # base_url is ever reached.
      allow(Tentacles::Authorization).to receive(:enabled?).and_return(true)

      expect { described_class.perform_now(note.id) }
        .to raise_error(described_class::WakeConfigurationError, /NEURAMD_S2S_URL/)
      # Not retryable — the slot is released so it does not stay consumed
      # by a permanent misconfiguration.
      expect(wake_state(note).last_wake_attempt_at).to be_nil
    end
  end
end
